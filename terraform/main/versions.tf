terraform {
  required_version = ">= 1.13.0"

  # Phase 2 で required_providers（aws ＋ awscc >= 1.66.0）をここに足す。
  # Phase 1 の時点ではプロバイダを使うリソースが1つも無いので、宣言しない。
}
