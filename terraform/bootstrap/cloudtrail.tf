# CloudTrail（D-013）。観点1で「いつ誰が設定を変えたか」を DevOps Agent が辿るために要る。
#
# 証跡用のバケットは state 用とは別に作る（Phase 1）。
# cloudtrail.amazonaws.com からの PutObject を許すバケットポリシーが必要で、state と同居させたくないため。

locals {
  cloudtrail_name = "${var.project}-trail"

  # 証跡バケットのポリシーは trail の ARN を条件に取り、trail はバケットを参照する。
  # resource 参照で書くと循環するので、ARN を文字列で組み立てる（AWS 公式の手順どおり）。
  cloudtrail_arn = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${var.bucket_prefix}-${var.project}-cloudtrail"

  # 撤収時に destroy できるようにする。証跡は検証期間限定（D-011）で残す価値が無い。
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# AWS 公式 "Amazon S3 bucket policy for CloudTrail" の記載どおり。
# https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-s3-bucket-policy-for-cloudtrail.html
# s3:x-amz-acl 条件は現行のドキュメントにも残っている（2026-08-03 に直接確認）。
data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck20150319"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite20150319"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_cloudtrail" "main" {
  name           = local.cloudtrail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  # 管理イベントのみ。データイベントは有効にしない（課金対象になる）。
  # アカウントで最初の1つの証跡は管理イベントが無料なので、multi-region でも追加費用は出ない。
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # バケットポリシーが無いと CreateTrail が InsufficientS3BucketPolicyException で落ちる
  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
