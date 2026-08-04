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
      # ⚠️ 属性名は integration だが、API は **integrationId** として検証する（D-044）。
      #    リテラル "GITHUB" を渡すと apply で落ちる。実測したエラー:
      #
      #      Value 'GITHUB' at 'integrationId' failed to satisfy constraint:
      #      Member must satisfy regular expression pattern: i-[a-zA-Z0-9\-]+
      #
      #    実値は GitHub App の認可時に払い出される i- 始まりの ID:
      #
      #      aws securityagent list-integrations \
      #        --query 'integrationSummaries[?provider==`GITHUB`].integrationId' --output text
      #
      #    service_id（D-043）と**まったく同じ形の誤り**で、これが3件目である。
      #    スキーマの属性名が実体を表していないため、plan では捕まらない。
      integration = var.security_agent_github_integration_id

      provider_resources = [
        {
          git_hub_repository = {
            owner = split("/", var.github_repository)[0]
            name  = split("/", var.github_repository)[1]
          }

          git_hub_capabilities = {
            # ⚠️ **false 固定。public リポジトリでは true にできない**（D-045）。
            #    true にすると apply が 400 で落ちる。API が返した原文:
            #
            #      Public GitHub repositories are supported for pentesting and
            #      not for code review comments.
            #
            #    「調査済みの外部事実」は Security Agent の PR コードレビューについて
            #    「リポジトリ可視性による制限は無い」と書いていたが、**それは誤りだった。**
            #    DevOps Agent 側の "Public repository limitation" と同じ制限が
            #    Security Agent にもある。**2つのエージェントで違うのは単一インストール制約のほうだけ。**
            #
            #    → これにより Phase 6 の項目10（PR にコードレビューコメントが付く）は
            #      D-010（public リポジトリ）と両立しない。判断は D-045 を参照。
            leave_comments = false

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

# --------------------------------------------------------------------------
# ペネトレーションテストのターゲットドメイン（Phase 5 / D-038）
# --------------------------------------------------------------------------
#
# ALB の DNS 名を検証対象として登録する。ドメインを取っていないので生の DNS 名を使う（D-007）。
#
# ⚠️ 登録と検証は別物である。ここでやるのは**登録**だけ。
#
#   登録   awscc_securityagent_target_domain（このリソース）
#   検証   aws securityagent verify-target-domain --target-domain-id <id>
#
# Terraform は検証を発火できない。awscc は Cloud Control API 越しの CRUDL しか行わず、
# verify-target-domain のような**アクション系 API を呼ぶ口を持たない**。
# verification_status は computed なので「読める」が、「待てる」わけではない。
# → 検証は apply の後に CLI で1回叩く。この切り分けが D-038 の結論である。
#
# ⚠️ ALB を作り直すと DNS 名が変わり、検証済みドメインが失効する（D-011）。
#    Phase 5 以降、ALB を破棄する変更を入れないこと。
#
# ペンテスト本体（awscc_securityagent_pentest）は**作らない**。$50 / task-hour（D-015）で、
# Terraform に置くと apply が課金を発火させることになり「デプロイ = terraform apply」（D-009）
# と相性が悪い。実行判断は人間が握る。D-040 で「検証まででフェーズを閉じる」と決めた。

resource "awscc_securityagent_target_domain" "pentest" {
  count = var.register_pentest_target_domain && var.domain_name != null ? 1 : 0

  # ⚠️ ALB の生 DNS 名ではなくカスタムドメインを登録する（D-042）。
  #    当初は aws_lb.main.dns_name を渡していたが、**検証が原理的に完了しない**。
  #    HTTP_ROUTE の検証は HTTPS で来て有効な証明書を要求し、
  #    *.elb.amazonaws.com に ACM のパブリック証明書は取得できない（AWS が所有するドメインのため）。
  target_domain_name = var.domain_name

  # ⚠️ HTTP_ROUTE ではなく DNS_TXT。**証明書が要らなくなるのが選定理由**（D-042）。
  #    検証用の TXT レコードは dns.tf が computed 属性からそのまま置く。
  verification_method = "DNS_TXT"

  # ⚠️ awscc に default_tags は無いので明示的に付ける。
  #    なお securityagent の tags は NESTING=list（devopsagent 側は set）。
  tags = [
    { key = "Project", value = var.project },
    { key = "ManagedBy", value = "terraform/main" },
  ]
}
