output "alb_dns_name" {
  description = <<-EOT
    アプリの入口。ドメインを取らない限りこれが唯一の到達先（D-007）。
    Phase 5 のペネトレーションテストで、ターゲットドメインとして登録するのもこの値。

    ⚠️ ALB を作り直すとこの名前は変わり、検証済みドメインが失効する。
    D-011 がキャンペーン型（期間中は立てっぱなし）を選んだ直接の理由がこれ。
  EOT
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "ブラウザで開く用"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecs_cluster_name" {
  description = "aws ecs describe-services 等で使う"
  value       = aws_ecs_cluster.main.name
}

output "dynamodb_table_name" {
  description = "アプリの TABLE_NAME 環境変数に入る値"
  value       = aws_dynamodb_table.submissions.name
}

output "log_group_name" {
  description = "アプリの構造化ログの出力先。アラームから辿る最初の場所"
  value       = aws_cloudwatch_log_group.app.name
}

output "devops_agent_space_id" {
  description = "DevOps Agent の Agent Space ID"
  value       = awscc_devopsagent_agent_space.main.agent_space_id
}

output "security_agent_space_id" {
  description = "Security Agent の Agent Space ID"
  value       = awscc_securityagent_agent_space.main.agent_space_id
}
