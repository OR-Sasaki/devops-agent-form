variable "project" {
  description = "リソース名の共通プレフィックス"
  type        = string
  default     = "devops-agent-form"
}

variable "region" {
  description = "全リソースのリージョン（D-008）"
  type        = string
  default     = "ap-northeast-1"
}

# --------------------------------------------------------------------------
# デプロイ
# --------------------------------------------------------------------------

variable "image_tag" {
  description = <<-EOT
    ECR のイメージタグ。実値はコミット SHA で、CI が渡す（D-013）。
    Terraform がイメージタグを所有するので drift が出ない。

    ⚠️ default を置かない。
    default があると、CI が -var を渡し忘れたときに「古い（あるいは存在しない）タグで
    apply が成功してしまう」。イメージタグはデプロイとコードを相関させる要（観点2）なので、
    間違った値で静かに通るより、渡し忘れで止まるほうがよい。

      ローカル  terraform plan -var image_tag=bootstrap   （Phase 2 のダミー値）
      CI        terraform plan/apply -var image_tag=$GITHUB_SHA
  EOT
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", var.image_tag))
    error_message = "image_tag は ECR のタグとして有効な文字列（英数字始まり、128文字以内）で指定すること。"
  }
}

variable "desired_count" {
  description = "ECS サービスのタスク数。1台だと「1台だけ落ちた」系の事象が作れない（D-013）"
  type        = number
  default     = 2
}

variable "task_cpu" {
  description = "Fargate のタスク CPU ユニット。0.25 vCPU（D-002 のコスト内訳）"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = <<-EOT
    Fargate のタスクメモリ (MiB)。0.5 GB（D-002 のコスト内訳）。
    ⚠️ Fargate はタスク単位のメモリを離散値でしか受け付けない（0.25 vCPU なら 512 / 1024 / 2048）。
    観点1-4「メモリを極端に小さくする」はここではなく、コンテナ側のハードリミットで表現する。
    fault-injection.tf を参照。
  EOT
  type        = number
  default     = 512
}

variable "container_port" {
  description = "アプリが listen するポート。Phase 3 の Hono もこの値を使う"
  type        = number
  default     = 3000
}

variable "admin_username" {
  description = <<-EOT
    /admin の Basic 認証のユーザー名（D-035）。**秘密ではない**ので平文で持つ。

    パスワードのほうはここに置かない。Terraform が random_password で生成し、
    SSM Parameter Store の SecureString 経由で ECS の secrets として注入する（ecs.tf）。
  EOT
  type        = string
  default     = "admin"
}

# --------------------------------------------------------------------------
# ネットワーク
# --------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC の CIDR。NAT Gateway は作らず public subnet ×2 だけを置く（D-002）"
  type        = string
  default     = "10.0.0.0/16"
}

variable "domain_name" {
  description = <<-EOT
    カスタムドメイン。**未指定のまま ALB の DNS 名で動くのが既定の姿**（D-007）。

    現時点では「値を受け取る口」だけを用意してある。Route53 ホストゾーン・ACM 証明書・
    HTTPS リスナーは、ドメインが実際に決まった時点で後付けする。
    ペネトレーションテストのターゲット検証は HTTP_ROUTE で ALB の生 DNS 名のまま通るため
    （調査済みの外部事実）、ドメインは構築のブロッカーにならない。
  EOT
  type        = string
  default     = null
}

# --------------------------------------------------------------------------
# 故障注入（D-005）— 今回は使わない。口を空けておくだけ
# --------------------------------------------------------------------------

variable "fault_injection" {
  description = <<-EOT
    観点1（AWS 設定起因）の切り替え口。**デフォルトの "none" が健全な状態**。

    値は 01-fault-perspectives.md 観点1 の #1-1〜#1-6 と 1 対 1 で対応する。

      none              健全（既定）
      iam_denied        1-1 タスクロールから dynamodb:PutItem を剥がす
      bad_healthcheck   1-2 ALB のヘルスチェックパスを存在しないパスにする
      closed_sg         1-3 ALB → タスクの SG ingress を閉じる
      low_memory        1-4 コンテナのメモリハードリミットを極端に下げる
      dynamodb_throttle 1-5 DynamoDB をオンデマンドから低容量プロビジョンドに変える
      broken_route      1-6 public subnet のデフォルトルートを落とす

    ⚠️ Phase 2 では使わない。D-005 は「器だけ作り、弾は後から込める」と決めている。
  EOT
  type        = string
  default     = "none"

  validation {
    condition = contains([
      "none",
      "iam_denied",
      "bad_healthcheck",
      "closed_sg",
      "low_memory",
      "dynamodb_throttle",
      "broken_route",
    ], var.fault_injection)
    error_message = "fault_injection は none / iam_denied / bad_healthcheck / closed_sg / low_memory / dynamodb_throttle / broken_route のいずれか。"
  }
}

# --------------------------------------------------------------------------
# ペネトレーションテストのターゲットドメイン検証（Phase 5）
# --------------------------------------------------------------------------
#
# 計画では Phase 3 の節に書かれているが、実体は ALB のリスナールールなので alb.tf にある。
# Phase 2 でまとめて書いた理由は D-030 を参照。

variable "pentest_verification_path" {
  description = <<-EOT
    HTTP_ROUTE 検証でトークンを置くパス。AWS が Phase 5 のブラウザ操作の途中で提示する。
    未指定なら検証用のリスナールールは作られない。
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.pentest_verification_path == null || can(regex("^/[A-Za-z0-9._~/-]*$", var.pentest_verification_path))
    error_message = "pentest_verification_path は / で始まるパスで指定すること。"
  }
}

variable "pentest_verification_token" {
  description = <<-EOT
    HTTP_ROUTE 検証で返すトークン。AWS が Phase 5 のブラウザ操作の途中で提示する。

    ⚠️ これは Secrets ではなく Variables に置く（D-020 と同じ扱い）。
    ALB 上で誰でも取得できるよう**公開配信するための値**であって、秘密ではないため。
  EOT
  type        = string
  default     = null
}

# --------------------------------------------------------------------------
# エージェント（Phase 5 のブラウザ操作の後に有効化する）
# --------------------------------------------------------------------------

variable "github_repository" {
  description = "エージェントに接続する GitHub リポジトリ。<owner>/<repo> 形式"
  type        = string
  default     = "OR-Sasaki/devops-agent-form"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository は <owner>/<repo> 形式で指定すること。"
  }
}

variable "github_repo_id" {
  description = "GitHub リポジトリの数値 ID。gh api repos/<owner>/<repo> --jq .id で取得する"
  type        = string
  default     = "1321456466" # OR-Sasaki/devops-agent-form
}

variable "connect_github_to_agents" {
  description = <<-EOT
    Agent Space に GitHub リポジトリを紐づけるかどうか。**既定は false**。

    ⚠️ true にできるのは、Phase 5 で GitHub App の認可（ブラウザ操作）を済ませた後だけ。
    認可前に true にすると、存在しない連携を参照して apply が落ちる。理由は D-029 を参照。
  EOT
  type        = bool
  default     = false
}

# --------------------------------------------------------------------------
# 可観測性
# --------------------------------------------------------------------------

variable "log_retention_days" {
  description = <<-EOT
    CloudWatch Logs の保持日数。検証期間が約1週間（D-011）なので短くてよい。
    長くしても撤収時にロググループごと消えるため、保持を延ばす意味が無い。
  EOT
  type        = number
  default     = 7
}
