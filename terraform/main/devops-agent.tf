# DevOps Agent の Agent Space とアカウント紐付け。
# AWS 公式サンプル aws-samples/sample-aws-devops-agent-terraform を下敷きにしている。
#
# ⚠️ ここで作る IAM ロールが「Agent Space ロール」である（CONTEXT.md）。
#    DevOps Agent が何を見え、何をできるかを決めるのはこのロールだけで、
#    Terraform を回すデプロイ用アイデンティティ（bootstrap の github-actions ロール）とは
#    完全に無関係。この2つは繰り返し混同されるので、必ず区別して呼ぶこと。

locals {
  # 信頼ポリシーの SourceArn に使う。Agent Space はまだ存在しないので ARN を組み立てる。
  # リソース側から参照すると循環になる。
  agentspace_arn_pattern = "arn:aws:aidevops:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:agentspace/*"
}

# --------------------------------------------------------------------------
# Agent Space ロール — Agent が監視対象を読むために assume する
# --------------------------------------------------------------------------

data "aws_iam_policy_document" "devops_agentspace_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }

    # 混乱した代理人（confused deputy）対策。
    # 他アカウントの Agent Space からこのロールを使われないように絞る。
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.agentspace_arn_pattern]
    }
  }
}

resource "aws_iam_role" "devops_agentspace" {
  name = "${var.project}-devops-agentspace"

  # IAM の description は ASCII 印字可能文字と Latin-1 補助しか通らない（Phase 1 で実測）
  description        = "Agent Space role for AWS DevOps Agent. Defines what the agent can observe."
  assume_role_policy = data.aws_iam_policy_document.devops_agentspace_trust.json
}

resource "aws_iam_role_policy_attachment" "devops_agentspace" {
  role       = aws_iam_role.devops_agentspace.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

# Resource Explorer のサービスリンクロール作成を許す。
# DevOps Agent はアカウント内のリソースを Resource Explorer 経由で走査してトポロジーを作るため、
# 初回にこのロールが必要になる。作成先を1つの ARN に固定しているので、
# 「任意のサービスリンクロールを作れる」わけではない。
data "aws_iam_policy_document" "devops_agentspace_slr" {
  statement {
    sid     = "AllowCreateResourceExplorerServiceLinkedRole"
    effect  = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer",
    ]
  }
}

resource "aws_iam_role_policy" "devops_agentspace_slr" {
  name   = "AllowCreateServiceLinkedRoles"
  role   = aws_iam_role.devops_agentspace.id
  policy = data.aws_iam_policy_document.devops_agentspace_slr.json
}

# --------------------------------------------------------------------------
# Operator App ロール — ウェブアプリの利用者セッション用
# --------------------------------------------------------------------------

data "aws_iam_policy_document" "devops_operator_trust" {
  statement {
    effect = "Allow"

    # ⚠️ sts:TagSession が要る。Agent Space ロールとの唯一かつ重要な差分。
    # Operator App は利用者ごとにタグ付きセッションを発行するため、これが無いと
    # Agent Space 作成時の信頼ポリシー検証で落ちる。
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.agentspace_arn_pattern]
    }
  }
}

resource "aws_iam_role" "devops_operator" {
  name = "${var.project}-devops-operator-app"

  description        = "Operator App role for AWS DevOps Agent web app sessions."
  assume_role_policy = data.aws_iam_policy_document.devops_operator_trust.json
}

resource "aws_iam_role_policy_attachment" "devops_operator" {
  role       = aws_iam_role.devops_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
}

# --------------------------------------------------------------------------
# IAM 伝播待ち
# --------------------------------------------------------------------------
#
# ⚠️ これを外すと初回 apply が不安定になる。
# Agent Space 作成時に Operator App ロールの信頼ポリシーが AWS 側で検証されるため、
# IAM の伝播が終わる前に呼ぶと失敗する。AWS 公式サンプルも同じ 30 秒を置いている。
#
# depends_on にポリシーのアタッチまで並べるのは、ロール本体だけでは足りないため。
# 待つべきなのは「ロールが最終的な権限を持った状態」の伝播である。

resource "time_sleep" "wait_for_devops_iam" {
  create_duration = "30s"

  depends_on = [
    aws_iam_role.devops_agentspace,
    aws_iam_role_policy_attachment.devops_agentspace,
    aws_iam_role_policy.devops_agentspace_slr,
    aws_iam_role.devops_operator,
    aws_iam_role_policy_attachment.devops_operator,
  ]
}

# --------------------------------------------------------------------------
# Agent Space
# --------------------------------------------------------------------------

resource "awscc_devopsagent_agent_space" "main" {
  name        = var.project
  description = "Agent Space for the DevOps Agent verification sandbox."

  operator_app = {
    iam = {
      operator_app_role_arn = aws_iam_role.devops_operator.arn
    }
  }

  # awscc プロバイダには default_tags が無いので明示的に付ける
  tags = [
    { key = "Project", value = var.project },
    { key = "ManagedBy", value = "terraform/main" },
  ]

  depends_on = [time_sleep.wait_for_devops_iam]
}

# 監視対象の AWS アカウントを紐づける。
# ⚠️ service_id はリテラル文字列 "aws"。AWS アカウント紐付け専用の値で、
#    ARN でもリソース ID でもない（Phase 0 のスキーマ検証と公式サンプルで確認済み）。
resource "awscc_devopsagent_association" "aws_account" {
  agent_space_id = awscc_devopsagent_agent_space.main.id
  service_id     = "aws"

  configuration = {
    aws = {
      assumable_role_arn = aws_iam_role.devops_agentspace.arn
      account_id         = data.aws_caller_identity.current.account_id

      # "monitor" は自アカウント監視。クロスアカウントなら "source"。
      account_type = "monitor"

      # 未指定 = アカウント内の全リソースが対象。専用アカウント（D-003）なので
      # 拾うものはすべて本プロジェクトのものになり、絞り込む必要が無い。
      #
      # ⚠️ ここに [] を書かないこと。**永続的な差分になる**（D-037）。
      #    API は未設定として保存し、refresh で null が返る。config に [] を書くと
      #    「null → []」の更新が毎回 plan に出続け、本物の変更が埋もれる。
      resources = null
    }
  }
}

# --------------------------------------------------------------------------
# GitHub 連携（Phase 5 のブラウザ操作の後に有効化する）
# --------------------------------------------------------------------------
#
# ⚠️ 既定では作られない（var.connect_github_to_agents = false）。理由は D-029。
#
# GitHub App の認可はブラウザ操作でしか行えず（D-004 の例外）、認可前にこの association を
# 作ろうとすると存在しない連携を参照することになる。**Phase 4 の初回 apply は必ず認可前**なので、
# 既定で有効にすると初回 apply がその場で落ちる。
#
# なお Terraform でどこまで書けるか自体が未確認である。
# awscc_devopsagent_service.service_details には git_hub が無い一方、
# association の configuration には git_hub{owner, owner_type, repo_id, repo_name} がある
# （スキーマで確認済み）。ブラウザ認可の後に service_id をどう得るのかは Phase 5 で実機確認する。

resource "awscc_devopsagent_association" "github" {
  count = var.connect_github_to_agents ? 1 : 0

  agent_space_id = awscc_devopsagent_agent_space.main.id

  # ⚠️ "aws" と違い、GitHub の service_id は**リテラルではなく認可時に払い出される UUID** である。
  #    D-029 はここに暫定で "github" と書いていたが、**それは誤りだった**（D-043）。
  #    実際の値は list-services で確認できる:
  #
  #      aws devops-agent list-services \
  #        --query 'services[?serviceType==`github`].serviceId' --output text
  #
  #    ⚠️ service_id は API から見ればただの文字列なので **plan では捕まらず apply で落ちる。**
  #       値はアカウント固有で AWS の認証情報が無いと読めないため、リポジトリ変数から渡す（D-020）。
  service_id = var.devops_agent_github_service_id

  configuration = {
    git_hub = {
      owner = split("/", var.github_repository)[0]
      # ⚠️ 小文字。許容値は "organization" / "user" の2つだけ（プロバイダの検証で確認）。
      # OR-Sasaki は個人アカウントなので "user"。
      # list-services の additionalServiceDetails.github.ownerType も "user" を返した。
      owner_type = "user"
      repo_name  = split("/", var.github_repository)[1]
      repo_id    = var.github_repo_id
    }
  }

  # service_id を渡し忘れたまま連携を有効にすると、null が API に届いて
  # 分かりにくいエラーで apply が落ちる。**plan の時点で止める。**
  # D-032 と同じ「間違った値で静かに通るより、渡し忘れで止まるほうがよい」という判断。
  lifecycle {
    precondition {
      condition     = var.devops_agent_github_service_id != null
      error_message = "connect_github_to_agents = true のときは devops_agent_github_service_id が必須（D-043）。aws devops-agent list-services --query 'services[?serviceType==`github`].serviceId' --output text で取得すること。"
    }
  }

  depends_on = [awscc_devopsagent_association.aws_account]
}
