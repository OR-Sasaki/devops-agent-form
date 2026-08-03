terraform {
  required_version = ">= 1.13.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws login の認証情報を読めるのは 6.23.0 以降（D-016）
      version = ">= 6.23.0"
    }
  }

  # backend は書かない。この層の state はローカル保持（D-013 / Phase 1）。
  # bootstrap は「state バケットそのものを作る層」なので、S3 バックエンドは使えない。
}
