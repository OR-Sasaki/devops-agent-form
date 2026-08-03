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
# ペネトレーションテストの HTTP_ROUTE 検証用ルート（Phase 5）
# --------------------------------------------------------------------------
#
# AWS がターゲットドメイン検証で提示するパスにトークンを置き、HTTP で取得させる。
# アプリ側ではなく ALB 側に置くのは、**アプリを再デプロイせずに値を差せる**ため。
#
# ⚠️ 値の出どころが Phase 5 で変わった（D-038）。
#
#   旧: ブラウザで提示された値を人がリポジトリ変数に入れ、-var で渡す
#   新: awscc_securityagent_target_domain が computed で返す値を**直接**参照する
#
# トークンが人手もリポジトリ変数も経由しなくなり、ブラウザ操作が丸ごと消えた。
# 登録と検証発火の切り分けは security-agent.tf のコメントを参照。
# ⚠️ ローカルから apply しない。apply 経路は CI 1本に保つ（D-009）。

resource "aws_lb_listener_rule" "pentest_verification" {
  count = var.register_pentest_target_domain ? 1 : 0

  listener_arn = aws_lb_listener.http.arn

  # デフォルトアクション（アプリへの forward）より先に評価させる。
  # アプリ側に同じパスのルートがあっても、検証はこのルールが確実に処理する。
  priority = 1

  condition {
    path_pattern {
      values = [awscc_securityagent_target_domain.pentest[0].verification_details.http_route.route_path]
    }
  }

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = awscc_securityagent_target_domain.pentest[0].verification_details.http_route.token
      status_code  = "200"
    }
  }
}
