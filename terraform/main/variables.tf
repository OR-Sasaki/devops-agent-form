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
    カスタムドメイン。**2026-08-04 に取得して既定値に入れた**（D-042）。

    ⚠️ 当初の想定（D-007）は「未指定のまま ALB の DNS 名で動くのが既定の姿。
    ペネトレーションテストのターゲット検証は HTTP_ROUTE で ALB の生 DNS 名のまま通るので、
    ドメインは構築のブロッカーにならない」だったが、**これは実測で覆った。**

      HTTP_ROUTE の検証は HTTPS で来て、有効な SSL 証明書を要求する。
      *.elb.amazonaws.com に ACM のパブリック証明書は取得できない。

    → ドメインは「後付け要素」ではなく**観点3のペネトレーションテストの前提条件**だった。
      検証方式も HTTP_ROUTE から DNS_TXT に切り替えた（証明書が不要になる）。

    null にすると Route53 のレコードもターゲットドメインも作られず、
    アプリは ALB の DNS 名だけで動く（D-007 の「未指定でも成立する」性質は保っている）。
  EOT
  type        = string
  default     = "gawacchi.link"
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
# ⚠️ 実体は dns.tf にある（D-042 で HTTP_ROUTE から DNS_TXT に切り替えたため）。
# 元は alb.tf のリスナールールだった。その経緯は D-030 と alb.tf のコメントを参照。

variable "register_pentest_target_domain" {
  description = <<-EOT
    ペネトレーションテストのターゲットドメイン（= var.domain_name）を Terraform で登録するか。
    **既定は false**。

    true にすると security-agent.tf の awscc_securityagent_target_domain が作られ、
    computed で返る verification_details.dns_txt の dns_record_name / dns_record_type / token が
    dns.tf の Route 53 レコードへ**直接**渡る。値が人手やリポジトリ変数を経由しない。

    ⚠️ var.domain_name が null だと何も作られない。ALB の生 DNS 名では検証が
    原理的に完了しないため、ドメインが要る（D-042）。

    ⚠️ 登録だけでは検証は完了しない。検証は別 API の発火が要る（D-038）。

      aws securityagent verify-target-domain --target-domain-id <id> --profile devopsagent

    ⚠️ 既定を false にしてあるのは D-029 と同じ理由。未検証の awscc リソースを
    初めて動かすので、失敗したときに「この変更のせい」と切り分けられる状態で有効化する。
  EOT
  type        = bool
  default     = false
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

    ⚠️ 効くのは **Security Agent 側だけ**である（D-044）。
    DevOps Agent 側の association はコンソールでの認可がその場で作ってしまうため、
    Terraform では管理していない（devops-agent.tf のコメントを参照）。

    ⚠️ true にするときは security_agent_github_integration_id も一緒に渡すこと。
  EOT
  type        = bool
  default     = false
}

variable "enable_pr_code_review_comments" {
  description = <<-EOT
    Security Agent に PR のコードレビューコメントを付けさせるか。**既定は false**（D-045）。

    ⚠️ **リポジトリが private のときしか true にできない。**
    public のまま true にすると apply が 400 で落ちる。API が返す原文:

      Public GitHub repositories are supported for pentesting and
      not for code review comments.

    ⚠️ Terraform はリポジトリの可視性を知らないため、これを事前に検証できない。
    **順序が唯一の防御である。**

      1. gh repo edit OR-Sasaki/devops-agent-form --visibility private
      2. gh variable set ENABLE_PR_CODE_REVIEW_COMMENTS --body true → deploy
      3. PR を出す（⚠️ draft では発火しない。必ず Ready for review にする）
      4. コメントを確認したら false に戻して deploy
      5. gh repo edit … --visibility public

    ⚠️ **4 を 5 より先に行うこと。** public に戻してから false にしようとすると、
    その apply 自体が「public なのに true」で落ちる。
  EOT
  type        = bool
  default     = false
}

variable "security_agent_github_integration_id" {
  description = <<-EOT
    Security Agent 側の GitHub 連携の integration ID（D-044）。

    ⚠️ **リテラル "GITHUB" ではない。** GitHub App の認可時に払い出される i- 始まりの ID である。
    awscc の属性名は integration だが、API は integrationId として
    `i-[a-zA-Z0-9\-]+` のパターンで検証する。

      aws securityagent list-integrations --profile devopsagent \
        --query 'integrationSummaries[?provider==`GITHUB`].integrationId' --output text

    アカウント固有で AWS の認証情報が無いと読めない値なので、
    リポジトリには置かずリポジトリ変数から渡す（D-020 と同じ扱い）。
  EOT
  type        = string
  default     = null

  # ⚠️ plan の出力に実値を出さない（D-047）。pr.yml は plan を PR にコメントするので、
  #    この属性に差分が出た瞬間に値が公開される経路になる。
  sensitive = true

  validation {
    condition     = var.security_agent_github_integration_id == null || can(regex("^i-[a-zA-Z0-9-]+$", var.security_agent_github_integration_id))
    error_message = "security_agent_github_integration_id は i- で始まる ID で指定すること（API の検証パターンに合わせる）。"
  }
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
