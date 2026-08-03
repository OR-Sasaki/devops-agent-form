# Security Agent の Agent Space。
# AWS 公式サンプル aws-samples/sample-terraform-for-security-agent を下敷きにしている。
#
# ##########################################################################
# ⚠️ awscc_securityagent_application を resource として書いてはいけない（D-019）。
#
# Application は**アカウントに1つ**で、2026-08-03 にコンソールから有効化済み。
# resource として書くと state に無い既存 Application と重複し、apply が落ちる。
#
# Agent Space は Application を参照しない（awscc_securityagent_agent_space に
# application 系の属性が存在しないことをスキーマで確認済み）ので、参照自体が不要。
# ID が要るようになったら読み取り専用の data source
# （awscc_securityagent_application / awscc_securityagent_applications）を使う。
#
# 同じ理由で、Application に付随する IAM ロールもここでは作らない。
# コンソールでの有効化時に application-<timestamp> という名前のロール
# （AWSSecurityAgentWebAppPolicy 付き）が既に作られており、Terraform で作ると二重管理になる。
# ⚠️ 計画が書いていた SecurityAgentAppRole-* という名前ではない。実物を確認した結果は
#    00-decisions.md の「Phase 2 の実機確認結果」を参照。
# ##########################################################################

resource "awscc_securityagent_agent_space" "main" {
  name        = var.project
  description = "Agent Space for AWS Security Agent. Code review and penetration testing."

  # 脅威モデリングとペネトレーションテストの文脈として、この構成のリソースを渡す。
  # Agent が「何を守る対象と見なすか」がここで決まる。
  aws_resources = {
    # ⚠️ log_groups だけ ARN ではなく**名前**を渡す（D-037）。
    #    ARN を渡すと API 側が名前に正規化して保存するため、refresh のたびに
    #    「/ecs/devops-agent-form → arn:aws:logs:…」の差分が出続ける。
    #    隣の iam_roles と vpcs は ARN のまま往復する。**同じリソースの中で扱いが違う。**
    log_groups = [aws_cloudwatch_log_group.app.name]
    iam_roles  = [aws_iam_role.ecs_task.arn, aws_iam_role.ecs_execution.arn]

    # ⚠️ vpcs は単一オブジェクトではなくリスト（スキーマで NESTING=list を確認）。
    # 単一オブジェクトで書くと validate が「list of object required」で落ちる。
    vpcs = [
      {
        vpc_arn     = "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:vpc/${aws_vpc.main.id}"
        subnet_arns = [for s in aws_subnet.public : "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:subnet/${s.id}"]
        security_group_arns = [
          "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:security-group/${aws_security_group.alb.id}",
          "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:security-group/${aws_security_group.ecs.id}",
        ]
      }
    ]
  }

  code_review_settings = {
    controls_scanning        = true
    general_purpose_scanning = true
  }

  # ⚠️ GitHub リポジトリの紐づけは、GitHub App の認可（ブラウザ操作）が済むまで有効にできない。
  #    既定は false なので、Phase 4 の初回 apply では何も紐づかない（D-029）。
  integrated_resources = var.connect_github_to_agents ? [
    {
      integration = "GITHUB"

      provider_resources = [
        {
          git_hub_repository = {
            owner = split("/", var.github_repository)[0]
            name  = split("/", var.github_repository)[1]
          }

          git_hub_capabilities = {
            # PR にコードレビューコメントを付ける。観点3 の主目的（Phase 6 の項目10）。
            leave_comments = true

            # ⚠️ false 固定。自動修復は D-014 でスコープ外。
            # Public リポジトリでは修正 PR ではなく diff 添付になるため、
            # true にしても「修正 PR が出る」動作は得られない。
            remediate_code = false
          }
        }
      ]
    }
    # ⚠️ else 側は [] ではなく null にする。**[] は永続的な差分になる**（D-037）。
    #    API は未設定として保存し refresh で null が返るため、
    #    config に [] を書くと「null → []」の更新が毎回 plan に出続ける。
  ] : null

  tags = [
    { key = "Project", value = var.project },
    { key = "ManagedBy", value = "terraform/main" },
  ]
}

# ペネトレーションテストのターゲットドメイン（awscc_securityagent_target_domain）と
# ペンテスト本体（awscc_securityagent_pentest）はここでは作らない。
#
#   ターゲットドメイン — ALB の DNS 名が要るので、ALB 作成後にしか登録できない。
#     加えて HTTP_ROUTE 検証を Terraform が「完了まで待てるか」が未確認である
#     （verification_details.http_route.route_path / .token は computed で読めることまでは
#      スキーマで確認済み）。Phase 5 で実機確認してから採否を決める。
#
#   ペンテスト — $50 / task-hour（D-015）。無料トライアルの残枠を確認してからでないと
#     予算上限 $100 の半分を1回で消費しうる。Terraform に置くと apply が課金を発火させることになり、
#     「デプロイ = terraform apply」（D-009）と相性が悪い。実行判断は人間が握る。
