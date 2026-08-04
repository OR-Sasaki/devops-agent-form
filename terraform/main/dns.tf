# カスタムドメイン（D-042）。
#
# ⚠️ このファイルは D-007 が「後付けする」と書いていたものの実体である。
#    ただし後付けした動機は D-007 の想定と違う。
#
#      D-007 の想定 — HTTPS を付けたくなったときの装飾。無くても観点3 は成立する
#      実際の理由   — **無いと観点3 のペネトレーションテストが成立しない**（D-042）
#
#    ターゲットドメインの検証が HTTPS と有効な証明書を要求し、
#    *.elb.amazonaws.com には ACM のパブリック証明書を取れないため。
#
# ⚠️ ホストゾーンは Terraform で**作らない**。
#    Route 53 でドメインを登録した時点で AWS が自動作成しており、
#    resource として書くと同名のゾーンが2つでき、NS レコードが食い違って名前解決が壊れる。
#    D-019（Security Agent の Application）と同じ形の失敗である
#    —— 「Terraform の外で先に成立しているもの」を resource で書いてはいけない。

data "aws_route53_zone" "main" {
  count = var.domain_name != null ? 1 : 0

  name         = "${var.domain_name}."
  private_zone = false
}

# apex を ALB に向ける。
#
# ⚠️ CNAME ではなく alias を使う。DNS の仕様上 apex に CNAME は置けない
#    （SOA / NS と共存できない）。alias は Route 53 独自の拡張で、この制約を受けない。
#    加えて alias はクエリ課金が無い。
resource "aws_route53_record" "apex" {
  count = var.domain_name != null ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

# --------------------------------------------------------------------------
# ペネトレーションテストのターゲットドメイン検証（DNS_TXT）
# --------------------------------------------------------------------------
#
# awscc_securityagent_target_domain（security-agent.tf）が computed で返す
# 検証用の TXT レコードを、そのままホストゾーンに置く。
#
# ⚠️ HTTP_ROUTE ではなく DNS_TXT を使う理由は D-042。
#    HTTP_ROUTE は HTTPS と有効な証明書を要求するが、DNS_TXT はどちらも要求しない。
#    ALB に 443 リスナーと ACM 証明書を足さずに済む。
#
# 検証の発火だけは Terraform から行えない（awscc は Cloud Control の CRUDL のみ）。
# apply の後に1回だけ叩く:
#
#   aws securityagent verify-target-domain --target-domain-id <id> --profile devopsagent

resource "aws_route53_record" "pentest_verification" {
  count = var.register_pentest_target_domain && var.domain_name != null ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = awscc_securityagent_target_domain.pentest[0].verification_details.dns_txt.dns_record_name
  type    = awscc_securityagent_target_domain.pentest[0].verification_details.dns_txt.dns_record_type

  # 検証は1回きりで、失敗したら短い TTL のほうが直しやすい。
  # デモ期間が約1週間（D-011）なのでキャッシュ効率を気にする理由が無い。
  ttl     = 60
  records = [awscc_securityagent_target_domain.pentest[0].verification_details.dns_txt.token]
}
