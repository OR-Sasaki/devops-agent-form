# 問い合わせフォームの送信内容を保存する（D-012）。
# オンデマンド課金なので、デモ規模では実質 $0（D-002 のコスト内訳）。

resource "aws_dynamodb_table" "submissions" {
  name = "${var.project}-submissions"

  # ⚠️ 観点1-5 の仕込み先（fault-injection.tf）。
  # PROVISIONED に切り替えて容量を 1 に絞ると書き込みスロットリングが発生する。
  billing_mode = local.fault_dynamodb_provisioned ? "PROVISIONED" : "PAY_PER_REQUEST"

  # PAY_PER_REQUEST のときは指定してはいけないので null にする。
  read_capacity  = local.fault_dynamodb_provisioned ? 1 : null
  write_capacity = local.fault_dynamodb_provisioned ? 1 : null

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # ⚠️ 有効にしない。D-011 の撤収（terraform destroy）が弾かれる。
  deletion_protection_enabled = false

  # PITR は有効にしない。検証期間 1週間（D-011）のデモデータに復旧の価値が無く、
  # ストレージ課金だけが増えるため。

  tags = {
    Name = "${var.project}-submissions"
  }
}
