output "github_actions_role_arn" {
  description = "gh variable set AWS_ROLE_ARN --body <この値>（D-020）"
  value       = aws_iam_role.github_actions.arn
}

output "tfstate_bucket" {
  description = "terraform/main/backend.tf の bucket に書く値"
  value       = aws_s3_bucket.tfstate.bucket
}

output "ecr_repository_url" {
  description = "Phase 4 の docker push 先"
  value       = aws_ecr_repository.app.repository_url
}

output "cloudtrail_bucket" {
  value = aws_s3_bucket.cloudtrail.bucket
}
