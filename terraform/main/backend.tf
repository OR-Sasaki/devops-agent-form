terraform {
  backend "s3" {
    # bucket は terraform/bootstrap/ の output tfstate_bucket。
    # アカウント ID をバケット名に含めていないのは、この値が Public リポジトリに
    # 平文で載るため（D-021）。
    bucket = "or-sasaki-devops-agent-form-tfstate"
    key    = "main/terraform.tfstate"
    region = "ap-northeast-1"

    encrypt = true

    # Terraform 1.10 以降のネイティブロック。DynamoDB テーブルは不要（D-013）。
    use_lockfile = true
  }
}

# ⚠️ ローカルからこの層を触るときは devopsagent-tf プロファイルを使うこと（D-016）。
#    S3 バックエンドは aws login の認証情報を直接読めないため、
#    devopsagent のままだと init が No valid credential sources found で落ちる。
#    CI は OIDC なのでこの制約を受けない。
