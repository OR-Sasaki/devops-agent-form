# ⚠️ アラームは症状ごとに必ず分離する（01-fault-perspectives.md 観点2 の設計制約）。
#
# メモリ・レイテンシ・エラー率を1つのアラームにまとめると、Agent が症状を切り分けられず
# RCA デモが成立しない。「何が鳴ったか」がそのまま「どこを見るべきか」になる粒度を保つこと。
#
# 閾値は**暫定値**である。デモを回しながら調整する前提で、02-implementation-plan.md の表を
# そのまま写してある。未定のままでは Terraform が書けないので置いてあるだけで、
# 実測に基づいた値ではない。

locals {
  # 02-implementation-plan.md Phase 2 のアラーム表と 1 対 1 で対応する。
  # 表を直すときはここも直す。
  alarm = {
    alb_5xx_threshold        = 5   # 合計 > 5 / 5分 × 1
    alb_latency_p95_seconds  = 1.0 # p95 > 1.0 秒 / 5分 × 2
    unhealthy_host_threshold = 1   # >= 1 / 1分 × 2
    ecs_cpu_threshold        = 80  # > 80% / 1分 × 3
    ecs_memory_threshold     = 80  # > 80% / 1分 × 2
    ddb_throttle_threshold   = 1   # >= 1 / 5分 × 1
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = var.log_retention_days
}

# --------------------------------------------------------------------------
# 通知先
# --------------------------------------------------------------------------
#
# サブスクリプションは作らない。宛先はメールアドレスしか無く、Public リポジトリに
# 平文で置けないため（D-022）。購読が要るときは手で足す。
#
# 購読ゼロでもトピックは無意味ではない — EventBridge ルールにはターゲットが要り、
# アラームの通知経路がどこに向いているかを構成として残す役割がある。

resource "aws_sns_topic" "alarms" {
  name = "${var.project}-alarms"
}

data "aws_iam_policy_document" "alarms_topic" {
  statement {
    sid    = "AllowCloudWatchAlarms"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alarms.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowEventBridge"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alarms.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.ecs_task_stopped.arn]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarms_topic.json
}

# --------------------------------------------------------------------------
# アラーム 1: ALB 5xx 率 — 観点 1-1 / 2-2
# --------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name        = "${var.project}-alb-5xx"
  alarm_description = "ALB 5xx count (ELB-origin + target-origin). Perspectives 1-1 and 2-2."

  comparison_operator = "GreaterThanThreshold"
  threshold           = local.alarm.alb_5xx_threshold
  evaluation_periods  = 1

  # ELB 由来と target 由来は原因が別（前者は LB 自身、後者はアプリ）だが、
  # 「5xx が出ている」という症状としては同じなので合算する。
  # どちらが立っているかは、鳴った後に個別のメトリクスを見れば分かる。
  #
  # ⚠️ 加算演算子を使う（SUM([m1,m2]) ではなく m1+m2）。
  #    ALB は HTTPCode_ELB_5XX_Count を「非ゼロのときだけ」報告するため、
  #    片方だけデータがある状況が普通に起きる。
  #    CloudWatch の公式ドキュメントは算術演算子について
  #    「Missing values in a time series are treated as 0」と明記しており、
  #    加算なら片方欠損でももう片方の値がそのまま出る。
  metric_query {
    id          = "e_total_5xx"
    expression  = "m_elb_5xx+m_target_5xx"
    label       = "ALB 5xx total"
    return_data = true
  }

  metric_query {
    id = "m_elb_5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
      }
    }
  }

  metric_query {
    id = "m_target_5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
        TargetGroup  = aws_lb_target_group.app.arn_suffix
      }
    }
  }

  # 5xx が出ていない = メトリクスが報告されない、が健全な状態。
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# --------------------------------------------------------------------------
# アラーム 2: ALB ターゲット応答時間 — 観点 2-3 / 2-4
# --------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name        = "${var.project}-alb-latency"
  alarm_description = "ALB target response time p95. Perspectives 2-3 and 2-4."

  namespace   = "AWS/ApplicationELB"
  metric_name = "TargetResponseTime"

  # 平均だと遅いリクエストが速いリクエストに薄められて、レイテンシ悪化が見えにくい。
  # ALB の公式ドキュメントも TargetResponseTime について
  # 「The most useful statistics are Average and pNN.NN (percentiles)」としている。
  extended_statistic = "p95"

  comparison_operator = "GreaterThanThreshold"
  threshold           = local.alarm.alb_latency_p95_seconds
  period              = 300
  evaluation_periods  = 2

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# --------------------------------------------------------------------------
# アラーム 3: ALB 異常ホスト — 観点 1-2 / 1-3
# --------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name        = "${var.project}-alb-unhealthy-hosts"
  alarm_description = "ALB unhealthy target count. Perspectives 1-2 and 1-3."

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"

  # ALB の公式ドキュメントの推奨に従う。原文:
  # 「We recommend you monitor for non-zero UnHealthyHostCount in the Minimum statistic,
  #   and alarm on non-zero value for more than one data point.」
  # Minimum は「全ての LB ノード・全 AZ が unhealthy と判定した」ときだけ非ゼロになるので、
  # デプロイ中の一時的なばらつきで鳴らない。1台だけ落ちた場合も、全ノードがそう見れば鳴る。
  statistic = "Minimum"

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = local.alarm.unhealthy_host_threshold
  period              = 60
  evaluation_periods  = 2

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  # ##########################################################################
  # ⚠️ このアラームだけ breaching にする。
  #
  # UnHealthyHostCount は「登録済みターゲットがあるときだけ報告される」
  # （ALB 公式ドキュメントの Reporting criteria: "Reported if there are registered targets"）。
  # つまり**タスクが全滅してターゲットが1つも登録されていない状態では、
  # メトリクスそのものが消える。** notBreaching にすると、最も重い障害が無音になる。
  #
  # 引き受けた代償 — トラフィックが完全に無い期間もデータが欠けうるため、
  # 誰もアクセスしていない時間帯にこのアラームが ALARM に落ちることがある。
  # 「全滅を見逃す」より「静かなときに鳴る」ほうがましだ、という判断（D-028）。
  # ##########################################################################
  treat_missing_data = "breaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# --------------------------------------------------------------------------
# アラーム 4: ECS CPU 使用率 — 観点 2-3
# --------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name        = "${var.project}-ecs-cpu"
  alarm_description = "ECS service CPU utilization. Perspective 2-3."

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  statistic   = "Average"

  comparison_operator = "GreaterThanThreshold"
  threshold           = local.alarm.ecs_cpu_threshold
  period              = 60
  evaluation_periods  = 3

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# --------------------------------------------------------------------------
# アラーム 5: ECS メモリ使用率 — 観点 1-4 / 2-1
# --------------------------------------------------------------------------

#
# ⚠️ 観点1-4 でこのアラームが鳴るかは**未確認**（D-034）。
#
# サービスの MemoryUtilization の分母は「タスク定義に指定されたメモリ」だが、
# 公式ドキュメントは同時に「soft limit があればそれを、無ければ hard limit (memory) を使う」とも書いており、
# **タスク単位の 512 MiB とコンテナ単位の 64 MiB のどちらが分母になるかが読み取れない。**
#   分母が 64 なら OOM 直前に 100% 近くまで上がって鳴る
#   分母が 512 なら 12.5% 程度にしかならず鳴らない
# どちらであっても観点1-4 の根拠は EventBridge のタスク停止イベント（下記）なので設計は成立するが、
# **この表の「1-4」の対応づけは実測で確かめるまで確定していない。** Phase 6 で観測する。
#
# 観点2-1（アプリのメモリリーク）は健全時の上限 512 MiB に対して漸増するので、こちらは素直に鳴る。
resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name        = "${var.project}-ecs-memory"
  alarm_description = "ECS service memory utilization. Perspective 2-1 (and possibly 1-4)."

  namespace   = "AWS/ECS"
  metric_name = "MemoryUtilization"
  statistic   = "Average"

  comparison_operator = "GreaterThanThreshold"
  threshold           = local.alarm.ecs_memory_threshold
  period              = 60
  evaluation_periods  = 2

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# --------------------------------------------------------------------------
# アラーム 6: DynamoDB スロットリング — 観点 1-5 / 2-4
# --------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttle" {
  alarm_name        = "${var.project}-dynamodb-throttle"
  alarm_description = "DynamoDB read/write throttle events. Perspectives 1-5 and 2-4."

  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = local.alarm.ddb_throttle_threshold
  evaluation_periods  = 1

  # ⚠️ 計画の表は ThrottledRequests を指定していたが、こちらに差し替えた（D-031）。
  #
  # DynamoDB の公式ドキュメントは ThrottledRequests のディメンションを
  # 「TableName, Operation」と記載している。同じページは SystemErrors について
  # 「A CloudWatch alarm that specifies only the TableName dimension never matches data
  #   and remains in the INSUFFICIENT_DATA state」と警告しており、
  # TableName 単独で張ったアラームが**静かに鳴らないまま**になる危険が現実にある。
  # Operation を固定すると PutItem / Scan ごとにアラームが増え、アプリ内部に結合してしまう。
  #
  # 一方 ReadThrottleEvents / WriteThrottleEvents は同ドキュメントが
  # 「The TableName dimension returns the ... for the table」と明記しており、
  # **TableName 単独で成立することが文書化されている。**
  # 症状（スロットリングが起きている）は同じで、読み書きの別まで分かる分こちらが細かい。
  metric_query {
    id          = "e_throttle"
    expression  = "m_read_throttle+m_write_throttle"
    label       = "DynamoDB throttle events"
    return_data = true
  }

  metric_query {
    id = "m_read_throttle"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "ReadThrottleEvents"
      period      = 300
      stat        = "Sum"
      dimensions = {
        TableName = aws_dynamodb_table.submissions.name
      }
    }
  }

  metric_query {
    id = "m_write_throttle"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "WriteThrottleEvents"
      period      = 300
      stat        = "Sum"
      dimensions = {
        TableName = aws_dynamodb_table.submissions.name
      }
    }
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# --------------------------------------------------------------------------
# ECS タスク停止イベント — 観点 1-4 / 1-6
# --------------------------------------------------------------------------
#
# これは CloudWatch アラームではない。閾値の概念が無いイベント通知である。
#
# stoppedReason に OOM（OutOfMemoryError）や ECR pull 失敗（CannotPullContainerError）の
# 理由が入るため、観点 1-4 / 1-6 では**アラームではなくこのイベントが根拠**になる。
# 調査の起点になるのは上のアラーム側で、こちらは Agent が辿る痕跡として置く。

resource "aws_cloudwatch_event_rule" "ecs_task_stopped" {
  name        = "${var.project}-ecs-task-stopped"
  description = "ECS task transitioned to STOPPED. Carries stoppedReason for RCA."

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Task State Change"]
    detail = {
      # クラスタで絞る。絞らないとアカウント内の他のクラスタも拾う。
      clusterArn = [aws_ecs_cluster.main.arn]
      lastStatus = ["STOPPED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ecs_task_stopped_sns" {
  rule      = aws_cloudwatch_event_rule.ecs_task_stopped.name
  target_id = "sns"
  arn       = aws_sns_topic.alarms.arn
}
