# イメージは bootstrap 層の ECR にある（D-013）。
# 層をまたぐ参照だが、remote state を読まず data source で引く。
# 名前（var.project）が両層で共通の規約になっているので、これで十分に決まる。
# bootstrap の state はローカルにしか無いため、remote state 参照は CI から成立しない。
data "aws_ecr_repository" "app" {
  name = var.project
}

resource "aws_ecs_cluster" "main" {
  name = var.project

  setting {
    name = "containerInsights"
    # "enhanced" / "enabled" / "disabled" の3値（ECS API リファレンス ClusterSetting で確認）。
    # enhanced はタスク・コンテナ単位のメトリクスまで自動収集する。
    # 観点2-1（メモリリークが漸増する）を「どのタスクで起きているか」まで見るのに要るので enhanced。
    value = "enhanced"
  }
}

# --------------------------------------------------------------------------
# IAM
# --------------------------------------------------------------------------
#
# ⚠️ これらは Agent Space ロールではない（CONTEXT.md）。
#    タスクが AWS API を叩くためのロールであって、DevOps Agent の可視範囲とは無関係。

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ECR からの pull と CloudWatch Logs への書き込みを行う。タスクではなく ECS エージェントが使う。
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project}-ecs-execution"

  # IAM の description は ASCII 印字可能文字と Latin-1 補助しか通らない。
  # 日本語を書くと CreateRole が ValidationError で落ちる（Phase 1 で実測）。
  description        = "ECS task execution role. Pulls the image from ECR and writes to CloudWatch Logs."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role = aws_iam_role.ecs_execution.name
  # ⚠️ service-role/ 配下にある。service-role を落とすと NoSuchEntity で apply が落ちる（実測）。
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# アプリ自身が使うロール。DynamoDB へのアクセスはここで決まる。
resource "aws_iam_role" "ecs_task" {
  name = "${var.project}-ecs-task"

  description        = "Application task role. Grants DynamoDB access to the form app."
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

data "aws_iam_policy_document" "ecs_task_dynamodb" {
  statement {
    sid    = "FormTableAccess"
    effect = "Allow"

    # ⚠️ 観点1-1 の仕込み先（fault-injection.tf）。
    # PutItem だけを抜くと、書き込みが全件失敗し参照は正常のままになる。
    # アプリが書き込みに使うのは PutItem だけなので、これで症状が「送信だけ 5xx」に揃う。
    actions = concat(
      ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"],
      local.fault_deny_dynamodb_write ? [] : ["dynamodb:PutItem"],
    )

    resources = [aws_dynamodb_table.submissions.arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_dynamodb" {
  name   = "dynamodb-access"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_dynamodb.json
}

# --------------------------------------------------------------------------
# /admin の Basic 認証パスワード（D-035）
# --------------------------------------------------------------------------
#
# ベースラインの /admin には認証を付ける。認証の無い管理エンドポイントは
# 観点3-4 の**故障そのもの**であり、最初から置くと Phase 6 項目10
# （この時点のコードに脆弱性は無い、という前提）が崩れるため。
#
# ⚠️ 値をリポジトリにもタスク定義の environment にも平文で置かない。
#    ハードコードすれば観点3-3（ハードコードされたシークレット）を先に仕込むことになる。
#    Terraform が生成 → SSM Parameter Store の SecureString → ECS の secrets で注入、と繋ぐ。
#
# ⚠️ 実行ロールに要るのは ssm:GetParameters **だけ**である。
#    ECS 公式ドキュメント（Amazon ECS task execution IAM role / Secrets Manager or
#    Systems Manager permissions）は kms:Decrypt について
#    「Required only if your secret uses a customer managed key and not the default key」
#    と明記している。ここは key_id を指定しない = 既定の AWS マネージドキー（alias/aws/ssm）
#    なので、KMS の許可は要らない。2026-08-03 に原文を直接確認した。
#
# 人間が値を読むときは、CI ではなく手元から取る（CI のログに出さないため）:
#   aws ssm get-parameter --name /devops-agent-form/admin-password \
#     --with-decryption --query Parameter.Value --output text --profile devopsagent

resource "random_password" "admin" {
  length = 32

  # 記号を使わない。Basic 認証の値として手でコピーする場面があり、
  # シェルやブラウザの URL 欄でのエスケープ事故のほうが現実的なリスクだから。
  # 英数字 32 文字（62^32 ≈ 2^190）で総当たりへの強度は十分に足りる。
  special = false
}

resource "aws_ssm_parameter" "admin_password" {
  name        = "/${var.project}/admin-password"
  description = "Basic auth password for the /admin console."
  type        = "SecureString"
  value       = random_password.admin.result

  tags = {
    Name = "${var.project}-admin-password"
  }
}

data "aws_iam_policy_document" "ecs_execution_secrets" {
  statement {
    sid       = "ReadAdminPassword"
    effect    = "Allow"
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.admin_password.arn]
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "ssm-secrets"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution_secrets.json
}

# --------------------------------------------------------------------------
# タスク定義
# --------------------------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = var.project
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    # ⚠️ 明示する。イメージをビルドするのは GitHub Actions の ubuntu-latest（x86_64）なので
    #    ARM64 にすると exec format error でタスクが起動しない。
    #    ローカルの Mac は arm64 なので、手元で build して push すると食い違う。
    cpu_architecture = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name  = var.project
      image = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"

      essential = true

      # ⚠️ 観点1-4 の仕込み先（fault-injection.tf）。
      # タスク単位ではなくコンテナ単位のハードリミット。超えると OOM で kill される。
      memory = local.container_memory_hard_limit

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        # ⚠️ 観点2 の必須要件。コミット SHA が構造化ログに乗らないと、
        #    Agent がアラームからコードまで降りてこられない（01-fault-perspectives.md）。
        #    SHA が残る3箇所は「構造化ログ・イメージタグ・ECS タスク定義」で、ここは1つ目と3つ目。
        { name = "COMMIT_SHA", value = var.image_tag },
        { name = "TABLE_NAME", value = aws_dynamodb_table.submissions.name },
        { name = "AWS_REGION", value = var.region },
        { name = "PORT", value = tostring(var.container_port) },
        { name = "NODE_ENV", value = "production" },
        # ユーザー名は秘密ではないので平文でよい。パスダウンは下の secrets 側（D-035）。
        { name = "ADMIN_USERNAME", value = var.admin_username },
      ]

      # ⚠️ environment ではなく secrets で渡す。
      #    environment に置くと値がタスク定義に平文で残り、コンソール・describe-task-definition・
      #    Terraform の plan 出力から読めてしまう。secrets なら参照（ARN）しか残らない。
      secrets = [
        { name = "ADMIN_PASSWORD", valueFrom = aws_ssm_parameter.admin_password.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # コンテナ単位のヘルスチェックは置かない。
      # ①イメージに curl / wget が要る（node:22-slim には無い）
      # ②ECS が勝手にタスクを差し替えると、仕込んだ故障が自己回復して観測できなくなる
      # 死活監視は ALB のターゲットヘルスチェックが担う（alb.tf）。
    }
  ])
}

# --------------------------------------------------------------------------
# サービス
# --------------------------------------------------------------------------

resource "aws_ecs_service" "app" {
  name            = var.project
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  depends_on = [
    # ALB のターゲット登録が始まる前にリスナーが存在している必要がある
    aws_lb_listener.http,

    # ⚠️ 実行ロールの権限は、タスクが起動を試みる前に揃っていなければならない。
    #    ロールへのポリシー付与はタスク定義からもサービスからも参照されないので、
    #    明示しないと Terraform は順序を保証しない。
    #    欠けたまま起動すると ResourceInitializationError（ECR pull / SSM 取得の失敗）になり、
    #    症状が観点1-6 や assign_public_ip の指定漏れと紛らわしくなる。
    aws_iam_role_policy_attachment.ecs_execution,
    aws_iam_role_policy.ecs_execution_secrets,
    aws_iam_role_policy.ecs_task_dynamodb,
  ]

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs.id]

    # ##########################################################################
    # ⚠️⚠️ これを消すとタスクが1台も起動しない。⚠️⚠️
    #
    # NAT Gateway を作らない構成（D-002）なので、タスクが外に出る経路は
    # 「ENI に付いた Public IP → IGW」しかない。
    # false だと ENI に Public IP が付かず、ECR から pull できず
    # CloudWatch Logs にも到達できないため、サービスが起動失敗を延々と繰り返す。
    #
    # ⚠️ その症状は観点1-6（ルート破壊で pull 失敗）と**完全に同一**である。
    #    仕込んでいない故障をデバッグする羽目になるので、絶対に消さないこと。
    #
    # Public IP × 2タスク分の課金は D-002 のコスト内訳に計上済み。
    # ##########################################################################
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project
    container_port   = var.container_port
  }

  # 起動直後はまだ listen していないので、その間の unhealthy を猶予する
  health_check_grace_period_seconds = 60

  # ⚠️ サーキットブレーカーとロールバックを有効にしない。
  #
  # 有効にすると、故障を仕込んだデプロイを ECS が自動で切り戻す。
  # 「壊れた状態が続いてアラームが鳴り続ける」ことがデモの前提（CONTEXT.md のインシデント面）
  # なので、自動回復すると観点1・2 のデモがそもそも観測できない。
  # 本番なら逆に必ず有効にする設定であり、ここはサンドボックス固有の判断である（D-027）。
  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # ⚠️ wait_for_steady_state は有効にしない（既定の false）。
  # 故障を仕込むと steady state に到達しないため、apply が延々とブロックする。
  # デプロイ完了待ちは deploy.yml 側で行う（Phase 4）。そちらならタイムアウトを制御できる。

  # DevOps Agent がトポロジーとタスクを対応づけられるよう、ECS 管理タグを伝播させる
  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  tags = {
    Name = var.project
  }
}
