# 予算アラート（D-015）。月 $100、実績 50/80/100% と予測 100% で通知する。
#
# ⚠️ Budgets は通知であって遮断ではない。実際に止めるのは terraform destroy（D-011）。
#
# Budgets はグローバルサービスで、SDK が us-east-1 の
# エンドポイント（budgets.amazonaws.com）へ自動的に解決する。
# そのため ap-northeast-1 のプロバイダのまま扱える（apply で実測して確認する）。

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # 実績ベース: 50% で「想定通り」、80% で「何かが余計に動いている」、100% で「止める判断」
  dynamic "notification" {
    for_each = [50, 80, 100]

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_notification_email]
    }
  }

  # 予測ベース: このままいくと上限に達する、を実績が届く前に知らせる
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_notification_email]
  }
}
