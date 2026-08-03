# ECR は bootstrap 側に置く（D-013）。
# terraform/main/ を destroy してもイメージが残るので、キャンペーンのたびに build し直さずに済む（D-011）。

resource "aws_ecr_repository" "app" {
  name = var.project

  # IMMUTABLE にしない。イメージタグはコミット SHA（D-013）なので、
  # 同じコミットで deploy.yml を再実行すると push が衝突して落ちる。
  # Phase 5 は「リポジトリ変数を入れて deploy.yml を再実行する」手順を含むため、
  # IMMUTABLE だとその手順が成立しない。
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # 撤収手順2（bootstrap も destroy する）を成立させるため。
  # イメージが残っていると force_delete なしでは destroy が失敗する。
  force_delete = true
}
