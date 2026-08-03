terraform {
  required_version = ">= 1.13.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws login の認証情報を読めるのは 6.23.0 以降（D-016）。
      # bootstrap 側と同じ制約に揃えてある。
      version = ">= 6.23.0"
    }

    awscc = {
      source = "hashicorp/awscc"
      # DevOps Agent / Security Agent のリソースを含む版。
      # Phase 0 のスキーマ検証はこの制約で解決した v1.95.0 に対して行った。
      version = ">= 1.66.0"
    }

    # Agent Space 作成時に IAM ロールの信頼ポリシーが検証されるため、
    # IAM 作成との間に伝播待ちを挟む（AWS 公式サンプルと同じ構成）。
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11.0"
    }

    # /admin の Basic 認証パスワードを生成する（D-035）。
    # 値をリポジトリに書けない以上、生成元がどこかに要る。
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }

  # backend は backend.tf に分けてある（S3 ＋ use_lockfile = true）。
}
