# ⚠️ profile をここに書かない。
#
# この層は S3 バックエンドを使うが、backend ブロックは変数もプロバイダ設定も読まない。
# バックエンドの認証は必ず環境（AWS_PROFILE / OIDC の環境変数）から取るので、
# プロバイダだけ profile を直書きすると「バックエンドは A、プロバイダは B」という
# ねじれが起きる。両方を環境から取れば経路が1本に揃う。
#
#   ローカル   AWS_PROFILE=devopsagent-tf terraform plan   （D-016 の credential_process 経由）
#   CI         OIDC が環境変数に一時認証情報を置く（D-009）
#
# bootstrap 側は S3 バックエンドを使わないので profile を直書きしている。層ごとに事情が違う。

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform/main"
    }
  }
}

# DevOps Agent / Security Agent は標準の aws プロバイダに存在しない（Phase 0 で確認）。
# awscc は Cloud Control API 経由なので、リソースによってはタグの扱いが aws プロバイダと異なる。
# default_tags に相当する仕組みが無いため、タグは各リソースで明示的に付ける。
provider "awscc" {
  region = var.region
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# public subnet を AZ 冗長にするために使う（D-013 の desired = 2）。
# AZ 名を直書きすると、アカウントごとの AZ マッピングの違いで再現性が落ちる。
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
