variable "project" {
  description = "リソース名の共通プレフィックス"
  type        = string
  default     = "devops-agent-form"
}

variable "bucket_prefix" {
  description = <<-EOT
    S3 バケット名をグローバル一意にするためのプレフィックス。
    アカウント ID は使わない — バケット名は backend.tf に書かれ Public リポジトリで公開されるため（D-021）。
  EOT
  type        = string
  default     = "or-sasaki"
}

variable "region" {
  description = "全リソースのリージョン（D-008）"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "aws login 済みのプロファイル。bootstrap は state がローカルなので devopsagent でよい（D-016）"
  type        = string
  default     = "devopsagent"
}

variable "github_repository" {
  description = <<-EOT
    OIDC の sub をこのリポジトリに限定する。<owner>/<repo> 形式。
    ⚠️ ここを緩めると任意のリポジトリからこのアカウントに入れる。Public リポジトリなので特に重要（Phase 1）。
  EOT
  type        = string
  default     = "OR-Sasaki/devops-agent-form"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository は <owner>/<repo> 形式で、ワイルドカードを含めてはいけない。"
  }
}

variable "github_owner_id" {
  description = "GitHub オーナーの数値 ID。gh api users/<owner> --jq .id で取得する（D-023）"
  type        = number
  default     = 15667196 # OR-Sasaki
}

variable "github_repo_id" {
  description = <<-EOT
    GitHub リポジトリの数値 ID。gh api repos/<owner>/<repo> --jq .id で取得する（D-023）。
    リポジトリを作るまで存在しないので、初回 apply の時点だけ null にできる。
    null の間は信頼ポリシーが旧形式の sub のままになるため、
    リポジトリ作成後は必ず実値を入れて再 apply すること。
  EOT
  type        = number
  default     = 1321456466 # OR-Sasaki/devops-agent-form
}

variable "budget_limit_usd" {
  description = "月次の予算上限（D-015）"
  type        = string
  default     = "100"
}

variable "budget_notification_email" {
  description = <<-EOT
    予算アラートの通知先（D-015）。管理アカウントのメールアドレス。
    default を置かない — Public リポジトリなのでメールアドレスを平文で載せない（D-022）。
    実値は gitignore 済みの terraform.tfvars に置く。
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.budget_notification_email))
    error_message = "budget_notification_email はメールアドレス形式で指定すること。"
  }
}
