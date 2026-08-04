resource "aws_lb" "main" {
  name               = var.project
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # ⚠️ false のままにする（既定値）。
  # true にすると terraform destroy が弾かれ、D-011 の撤収手順が回らなくなる。
  enable_deletion_protection = false

  # アクセスログは S3 バケットが要るうえ、DevOps Agent が調査に使うのは
  # CloudWatch のメトリクスとアプリの構造化ログ（observability.tf）。
  # 検証期間 1週間（D-011）に対して置き場を増やす価値が無いので有効化しない。

  tags = {
    Name = var.project
  }
}

resource "aws_lb_target_group" "app" {
  name        = var.project
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # awsvpc の Fargate タスクは ENI の IP で登録される

  # 既定の 300 秒だとデプロイのたびに5分待つことになる。
  # 観点1・2 のデモは何度も回すので、待ち時間はそのまま検証速度に効く。
  deregistration_delay = 30

  health_check {
    enabled = true
    # ⚠️ 観点1-2 の仕込み先（fault-injection.tf）。
    path                = local.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = var.project
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # HTTPS リスナーは作らない。ドメインが未定で ACM 証明書を発行できないため（D-007）。
  # ドメインが決まったら、ここに 443 のリスナーを足し、80 はリダイレクトに変える。

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# --------------------------------------------------------------------------
# ペネトレーションテストの検証用ルートは、ここには無い
# --------------------------------------------------------------------------
#
# ⚠️ かつてここに HTTP_ROUTE 検証用の fixed-response ルールがあったが、
#    **検証方式を DNS_TXT に切り替えたので削除した**（D-042）。現在の実体は dns.tf にある。
#
# 削除に至るまでに実測で分かったことを残す。どれも「apply は通るのに動かない」種類なので、
# 同じ形の誤りを別の場所でやらないために書いてある。
#
#   1. **API が返す routePath には先頭の / が付かない。**
#        "routePath": ".well-known/aws/securityagent-domain-verification.json"
#      ALB の path-pattern は / で始まらないと一致しないため、そのまま渡すと
#      ルールは作られるが永久に一致せず、リクエストはアプリへ流れて 404 になる
#   2. **トークンは生ではなく JSON で返す。** 公式指定は { "tokens": ["<token>"] }
#   3. **そもそもこの経路では検証が完了しない。** 検証は HTTPS で来て有効な証明書を要求し、
#      *.elb.amazonaws.com に ACM のパブリック証明書は取れない（D-042）
#
# 1 と 2 は直して実際に 200 と正しい JSON が返るところまで確認した。
# そのうえで 3 が原理的な壁だったので、経路ごと差し替えている。
