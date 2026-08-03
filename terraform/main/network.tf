# ⚠️ NAT Gateway を作らない（D-002 の設計制約）。
#
# 教科書通りにタスクをプライベートサブネットへ置くと NAT だけで月 $35 かかり、
# アプリ本体（Fargate 2タスクで $22.5）より高くつく。
# 代わりにタスクを public subnet に置き、ENI に直接 Public IP を付ける。
# その代償が Public IPv4 の課金（4アドレス分 $14.6/月）で、D-002 の内訳に計上済み。
#
# この選択の帰結は ecs.tf の assign_public_ip = true に現れる。**あれが無いと何も起動しない。**

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # DevOps Agent がトポロジーを描くとき、および ECS のサービスディスカバリで名前解決が要る
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.project
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.project
  }
}

# AZ 冗長のために2つ作る（D-013 の desired = 2）。
# AZ 名を直書きしないのは、AZ 名と物理 AZ の対応がアカウントごとに違うため。
resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Fargate のタスク ENI は ecs.tf の assign_public_ip で Public IP を得るため、
  # この設定は実際には効かない。「これは public subnet である」という意思表示として置く。
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-public-${count.index + 1}"
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-public"
  }
}

# ⚠️ 観点1-6 の仕込み先。count = 0 にするとデフォルトルートが消え、
#    ECR からの pull と CloudWatch Logs への送信が両方落ちる（fault-injection.tf）。
resource "aws_route" "public_default" {
  count = local.fault_break_default_route ? 0 : 1

  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --------------------------------------------------------------------------
# セキュリティグループ
# --------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "ALB. Accepts HTTP from the internet and forwards to ECS tasks."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-alb"
  }
}

resource "aws_security_group" "ecs" {
  name        = "${var.project}-ecs"
  description = "ECS Fargate tasks. Ingress from the ALB only."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-ecs"
  }
}

# ペネトレーションテストが外部から到達できる必要がある（01-fault-perspectives.md 観点3）。
# ここを絞ると観点3のデモが成立しない。
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet. Required for pentest reachability."

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id = aws_security_group.alb.id
  description       = "Forward traffic and health checks to the tasks."

  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# ⚠️ 観点1-3 の仕込み先。count = 0 にすると ALB からタスクへ到達できなくなる。
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  count = local.fault_close_ecs_ingress ? 0 : 1

  security_group_id = aws_security_group.ecs.id
  description       = "Traffic from the ALB."

  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# NAT が無いので、ECR からの pull・CloudWatch Logs への送信・DynamoDB へのアクセスは
# すべてこの egress を通って IGW へ抜ける。ここを絞ると観点1-6 と同じ症状になる。
resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  description       = "ECR pull, CloudWatch Logs, DynamoDB. All egress via the IGW (no NAT)."

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
