# terraform/main/ の state を置く S3 バケット（D-009 / D-013）。
# CloudTrail 証跡用とは別バケットにする — 証跡側は cloudtrail.amazonaws.com からの
# 書き込みを許すバケットポリシーが要るため、state と混ぜない（Phase 1）。

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.bucket_prefix}-${var.project}-tfstate"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
