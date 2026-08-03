provider "aws" {
  region = var.region

  # S3 バックエンドを使わない層なので、credential_process を挟まず
  # aws login のプロファイルをそのまま使える（D-016 / Phase 0 項目2 で実測）。
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform/bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}
