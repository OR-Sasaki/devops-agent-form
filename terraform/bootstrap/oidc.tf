# GitHub Actions のデプロイ用アイデンティティ（D-009）。
# ⚠️ これは Agent Space ロールではない。DevOps Agent が何を見えるかとは無関係（CONTEXT.md）。

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # thumbprint_list は指定しない。AWS が自前の信頼済み CA で TLS を検証するため
  # GitHub の OIDC プロバイダでは使われず、aws プロバイダ 6.57.1 でも必須ではない（実測）。
}

locals {
  github_owner = split("/", var.github_repository)[0]
  github_repo  = split("/", var.github_repository)[1]

  # GitHub の OIDC トークンの sub には2つの形式がある（D-023）。
  #
  # 旧形式   repo:OWNER/REPO:...                        2026-07-15 より前に作られたリポジトリ
  # 不変形式 repo:OWNER@OWNER-ID/REPO@REPO-ID:...       2026-07-15 以降に作られたリポジトリの既定
  #
  # どちらが発行されるかはリポジトリの作成日と OIDC 設定で決まるため、両方を許可する。
  # ⚠️ ID 部分にワイルドカードを使ってはいけない。不変形式が防いでいる
  #    「ユーザー名の再取得によるなりすまし」をそのまま無効化してしまう。
  github_subs = concat(
    ["repo:${var.github_repository}:*"],
    var.github_repo_id == null ? [] : [
      "repo:${local.github_owner}@${var.github_owner_id}/${local.github_repo}@${var.github_repo_id}:*"
    ],
  )
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # ⚠️ sub をこのリポジトリに厳密に絞る。
    # 絞らないと任意の GitHub リポジトリからこのアカウントに入れる。
    # このロールは AdministratorAccess を持つので、緩めるとアカウントを丸ごと渡すことになる。
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subs
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project}-github-actions"

  # IAM の description は ASCII 印字可能文字と Latin-1 補助しか受け付けない。
  # 日本語を入れると CreateRole が ValidationError で落ちる（2026-08-03 に実測）。
  description = "Deployer identity assumed by GitHub Actions via OIDC. Not the Agent Space role."

  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600
}

# CI が実質 Administrator 相当を持つのは D-009 で引き受けたリスク。
# 専用アカウント（D-003）なので爆発半径はこのアカウント内に閉じている。
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
