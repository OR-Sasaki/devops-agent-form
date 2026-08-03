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
  # 旧形式   repo:OWNER/REPO:...                    2026-07-15 より前に作られたリポジトリ
  # 不変形式 repo:OWNER@OWNER-ID/REPO@REPO-ID:...   2026-07-15 以降に作られたリポジトリの既定
  #
  # ⚠️ 両方を並べてはいけない。旧形式は「オーナー名を誰かが再取得すると
  #    同じ sub を作れてしまう」問題を抱えており、不変形式はそれを塞ぐために存在する。
  #    このロールは AdministratorAccess を持つので、旧形式を残すと
  #    OR-Sasaki が改名・削除されたときにアカウントを丸ごと奪われる経路が復活する。
  #
  # ⚠️ ID 部分にワイルドカードを使ってはいけない。理由は上と同じ。
  #
  # github_repo_id が null なのは「リポジトリをまだ作っていない」状態だけ。
  # そのときは旧形式で置いておき、リポジトリ作成後に ID を渡して不変形式へ切り替える。
  github_subs = var.github_repo_id == null ? [
    "repo:${var.github_repository}:*"
    ] : [
    "repo:${local.github_owner}@${var.github_owner_id}/${local.github_repo}@${var.github_repo_id}:*"
  ]
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
