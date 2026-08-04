# 決定ログ

グリルセッションで確定した決定を、決まった順に記録する。用語は [CONTEXT.md](../../CONTEXT.md) に従う。

**ステータス: 決定確定（D-001〜D-047）／Phase 0・Phase 1・Phase 2・Phase 3・Phase 4 完了／Phase 5・Phase 6 進行中／検証期間は 2026-08-10 頃まで**
2026-08-02 のグリルセッションで全項目を解消。同日の外部レビューを受けて D-014・D-015 を追加し、[D-002](#d-002-実行基盤は-ecs-fargate--alb--dynamodb) のコスト見積りと [D-008](#d-008-リージョンは-ap-northeast-1-に統一) のリスク認識を訂正した。
同日の [Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) の実機確認で D-016・D-017 を追加し、[D-008](#d-008-リージョンは-ap-northeast-1-に統一) の「3目標すべて東京で成立する」という記述を**再度訂正した**（[D-017](#d-017-目標2-の到達点を-agent-ready-specification-に縮小する) を参照）。
[Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) 完了時に D-018・D-019 を、Phase 1 の着手準備で D-020 を追加した。
[Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) の実施中に、公開リポジトリへの露出に関する判断として D-021・D-022 を追加し、初回 push 直前の外部レビュー（Codex）の指摘を受けて D-023〜D-025 を追加した。
[Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) で `terraform/main/` を書く過程で D-026〜D-033 を追加し、**アラーム表のメトリクスを1件訂正した**（[D-031](#d-031-dynamodb-のスロットリング監視は-throttleevents-で行う)）。初回コミット後の外部レビュー（7回目）を受けて D-034 を追加した。
[Phase 3](./02-implementation-plan.md#phase-3-アプリ)・[Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の着手時に、計画が決めていなかった2件（`/admin` の認証と fork からの PR の扱い）を D-035・D-036 として決めた。初回 apply の後に永続的な差分が見つかり D-037 を追加した。
[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続)・[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の実施中に、未決だった判断4件を D-038〜D-041 として決め、**[D-007](#d-007-ドメインは決め打ちしない) と [D-028](#d-028-異常ホストアラームは-minimum-統計で見る) の前提が実測で覆った**ため D-042 を追加した。以降に新しい判断が生じたら D-043 以降として追記する。

---

## 調査済みの外部事実

グリル中に実際に確認した事実。推測ではない。

### AWS DevOps Agent

| 項目 | 事実 |
|---|---|
| 提供状況 | GA 済み |
| 対応リージョン | 11リージョン。us-east-1 / us-west-2 / ca-central-1 / sa-east-1 / ap-south-1 / ap-southeast-1 / ap-southeast-2 / **ap-northeast-1** / eu-central-1 / eu-west-1 / eu-west-2 （[Supported Regions](https://docs.aws.amazon.com/devopsagent/latest/userguide/about-aws-devops-agent-supported-regions.html) を 2026-08-02 に直接再確認。サービスエンドポイントも11個掲載されている） |
| **機能別のリージョン制限** | 公式に「Feature availability by Region」表がある。**Production operations（investigations / recommendations / prevention）・On-demand DevOps tasks・Custom agents は全リージョン。** **Release management（release readiness review / release testing）は us-east-1 のみ（preview）。** Sandbox（preview）は us-east-1 / us-west-2 / ap-northeast-1 / eu-west-1 |
| **コード変更の出力形式** | **PR を新規に開くという記述は公式ドキュメントに確認できなかった**（記述が無いだけで、機能が無いことの証明ではない）。確認できた形態は3つ。①Production operations の調査・改善提案は **agent-ready specification**（「a structured document that can be handed directly to a coding agent for implementation」）を生成し、実装は Kiro 等の別エージェントか人間が行う ②Release management の release readiness code review は**既存の PR に対するインラインコメント**（「Findings appear as inline comments on the affected lines of code」）③chat から「Request the agent generate a fix for an identified issue」— **配信形式の記載は無い**。なお GitHub App は Contents を read-write で要求し「propose fixes」と説明されるため、**PR 作成に必要な権限自体は持っている**。判断は [D-017](#d-017-目標2-の到達点を-agent-ready-specification-に縮小する) を参照 |
| **public リポジトリの制限** | 公式ドキュメントに独立した見出し「Public repository limitation」がある。原文: 「Automated PR/MR code review triggers are only available for private repositories. DevOps Agent does not automatically review pull requests or merge requests on public repositories.」 理由は「anyone can open a pull request against a public repository」。**ただし public でも chat や coding agent 連携（Kiro Power / Claude Code plugin / AWS Transform custom）経由なら release readiness code review 自体は実行できる**（自動発火しないだけ） |
| GitHub App の権限 | Read & Write（既定）で Checks / Workflows / Actions / Contents / Pull requests が read-write、Organization administration が read。Contents の write は「propose fixes」、Pull requests の write は「posting inline review comments」と説明されている。Read Only も選べる |
| スコープ | Agent Space はどのリージョンに作っても、紐づけたアカウントの全リージョンを監視できる |
| 課金 | agent-second 課金。$0.0083 / agent-second。1回の調査（5〜10分）で $2.5〜5 程度 |
| 無料枠 | 2ヶ月トライアル（Investigations 20h / Evaluations 15h / On-demand SRE 20h） |
| 前提条件 | ①実際にデプロイされたアプリ ②メトリクス・ログが出ていること（CloudWatch ネイティブで可、追加接続不要） ③Agent 用 IAM ロール |
| Terraform | **標準の `hashicorp/aws` プロバイダには無い。** `hashicorp/awscc` を使う。リソース名は実在確認済み（下の「awscc プロバイダのスキーマ検証」を参照）。AWS 公式に [Terraform 版の getting started](https://docs.aws.amazon.com/devopsagent/latest/userguide/getting-started-with-aws-devops-agent-getting-started-with-aws-devops-agent-using-terraform.html) と公式サンプル [aws-samples/sample-aws-devops-agent-terraform](https://github.com/aws-samples/sample-aws-devops-agent-terraform)（2026-07-23 更新）がある |
| 主な連携先 | GitHub（コード＋デプロイイベント）、PagerDuty、Grafana、Azure DevOps、EventBridge |
| **公式ドキュメント内の矛盾** | [Terraform の getting started ページ](https://docs.aws.amazon.com/devopsagent/latest/userguide/getting-started-with-aws-devops-agent-getting-started-with-aws-devops-agent-using-terraform.html)は「available in the following 6 AWS Regions」と書いているが、[Supported Regions ページ](https://docs.aws.amazon.com/devopsagent/latest/userguide/about-aws-devops-agent-supported-regions.html)は11リージョンを表とエンドポイント一覧の両方で掲げている。**専用ページである後者を採る。** 検索エンジンの要約は前者を拾って「6リージョン」と答えるため、要約を信用してはいけない実例 |

### AWS Security Agent

| 項目 | 事実 |
|---|---|
| 対応リージョン | 9リージョン。**ap-northeast-1 を含む**（GitHub アクセス元 IP の一覧に東京あり） |
| **自動修復の配信方式** | **リージョンではなくリポジトリ可視性で決まる。** 公式ドキュメント [Remediate code review findings](https://docs.aws.amazon.com/securityagent/latest/userguide/remediate-code-scan-findings.html) を 2026-08-02 に直接再確認。原文: 「For private repositories, AWS Security Agent opens a pull request with the proposed fix. For public repositories, AWS Security Agent attaches a downloadable diff to the finding that you can apply locally.」 同ページに**リージョンに関する記述は一切ない**（当初「us-east-1 限定」と誤認していた点の裏取り）。→ [D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) で Public を選んだ時点で、**どのリージョンでも修正 PR は出ない**。[D-014](#d-014-security-agent-の自動修復はスコープ外) でスコープ外とした |
| 課金 | オンデマンドペネトレーションテスト **$50 / task-hour**。2ヶ月の無料トライアルあり |
| Terraform | `awscc_securityagent_agent_space` あり。AWS 公式サンプル [aws-samples/sample-terraform-for-security-agent](https://github.com/aws-samples/sample-terraform-for-security-agent)（2026-07-03 更新）が `iam.tf` / `security-agent.tf` 等を提供 |
| 作成されるもの | Application（アカウントに1つ）、`SecurityAgentAppRole-*`（`AWSSecurityAgentWebAppPolicy`）、`SecurityAgentServiceRole-*`（ペンテスト用）、Agent Space、（任意）Target Domain、（任意）Pentest |
| 機能 | PR の差分コードレビュー（GitHub 上にコメント）、リポジトリ全体スキャン、脅威モデリング、ペネトレーションテスト、自動修復（[D-014](#d-014-security-agent-の自動修復はスコープ外) でスコープ外） |
| PR コードレビューの挙動 | 「Ready for review」で発火（draft は対象外）。解析開始時にコメントを出し、完了後に指摘をまとめて1レビューで投稿。**指摘ゼロでも `No issues identified.` とコメントする** → 脆弱性を仕込まなくても接続確認に使える。~~リポジトリ可視性による制限は無い~~ **← 誤り。下記を参照** |

> **⚠️ 「リポジトリ可視性による制限は無い」は誤りだった（2026-08-04 に実測）。**
> `git_hub_capabilities.leave_comments = true` で apply したところ、**API が 400 で拒否した。** 返ってきた原文:
>
> ```
> Public GitHub repositories are supported for pentesting and not for code review comments.
> ```
>
> **これは検索結果の要約ではなく、AWS のサービス自身が拒否した一次観測である。**
> `list-integrated-resources` も接続先を `"accessType": "PUBLIC"` として記録しており、可視性を見ていることが分かる。
>
> → **DevOps Agent 側の「Public repository limitation」と同じ制限が Security Agent にもある。**
> [D-006](#d-006-security-agent-も併せて導入する) と [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) の注意書きは「2つのエージェントで制約が違う」と書いていたが、
> **違うのは GitHub App の単一インストール制約のほうだけで、public リポジトリの PR コードレビュー制限は両方にかかる。**
> 帰結は [D-045](#d-045-コードレビューを見るときだけ一時的に-private-にする) を参照。

**GitHub 連携（公式ドキュメントで確認済み）**

- **個人ユーザーアカウントで連携可能。** 登録時の Account type に `Organization` と **`User`** の選択肢がある → `OR-Sasaki` のままで良く、GitHub organization を新設する必要はない
- **GitHub App は1つの GitHub アカウントに一度しかインストールできない（Security Agent の話。DevOps Agent は違う）。** [Connect to GitHub](https://docs.aws.amazon.com/securityagent/latest/userguide/connect-github.html) に「A GitHub App can only be installed once to a GitHub account or GitHub organization. If you need to connect the same GitHub organization to AWS Security Agent, you must use the same AWS account where the integration was first registered.」とある。つまり `OR-Sasaki` は**ただ1つの AWS アカウント**にしか紐づけられない。デモアカウントに紐づけると、後から別アカウントで使いたくなったらアンインストールが必要
  → **DevOps Agent には同じ制約は無い。** [What's new](https://docs.aws.amazon.com/devopsagent/latest/userguide/whats-new.html) の 2026-06-30 の項に「You can now connect AWS DevOps Agent in multiple AWS accounts and Regions to the same GitHub organization or account. If the AWS DevOps Agent GitHub App is already installed, additional accounts and Regions reuse the existing installation」とある。**2つのエージェントで制約が違うので、まとめて扱わないこと**
- リポジトリ選択は **All / Only select repositories** から選べる → **必ず "Only select repositories"** を選ぶこと。All を選ぶと既存の 27 リポジトリすべてが Security Agent のスコープに入る

**ペネトレーションテストのターゲットドメイン検証**

- 検証方式は **DNS_TXT** / **HTTP_ROUTE** / **PRIVATE_VPC** の3つ（CLI の `create-target-domain --verification-method` の許容値で確認）。**AWS はテストを検証済みドメインに対してのみ実行する**
- **検証の発火は独立した API である。** `aws securityagent verify-target-domain --target-domain-id <id>`。登録（`create-target-domain`）とは別物で、**Terraform からは発火できない**（[D-038](#d-038-ターゲットドメインは-terraform-で登録し検証発火は-cli-で行う)）
- ~~**ALB が対象の場合は HTTP_ROUTE が推奨。** エージェントがパスとトークンを提示し、HTTP で取得して検証する。ALB は元々到達可能なのでそのまま通る~~
- ~~→ **カスタムドメインは必須ではない。** ALB の生 DNS 名で成立する~~

> **⚠️ この2行は誤りだった（2026-08-03 に実測で判明）。** 詳細と対応は [D-042](#d-042-http_route-検証は-https-と有効な証明書を要求するドメインを取得して-dns_txt-に切り替える) を参照。
> **HTTP_ROUTE の検証リクエストは HTTPS で来る。** 公式ドキュメント [Enable an application domain for penetration testing](https://docs.aws.amazon.com/securityagent/latest/userguide/enable-test-domain.html) を 2026-08-03 に直接確認した。原文:
>
> - 「Return to the Target Domains table, select the domain, and choose **Verify**. AWS Security Agent sends an **HTTPS GET** request to the verification URL and validates the token.」
> - 「If the domain is accessible on the public internet, make sure that your domain has a **valid SSL certificate** before running verification.」
>
> 実際に `verify-target-domain` を叩いた結果も同じで、**`https://` で取りに来て接続タイムアウトした**（本構成の ALB はポート 80 のみ）。
>
> ```
> Verification failed for https://devops-agent-form-….elb.amazonaws.com/.well-known/aws/securityagent-domain-verification.json:
> connection timed out while attempting to query endpoint
> ```
>
> **`*.elb.amazonaws.com` に対して ACM のパブリック証明書は取得できない**（ドメインを所有しているのは AWS であり、DNS/メール検証を通せない）。
> したがって **ALB の生 DNS 名では HTTP_ROUTE 検証は原理的に完了しない。**

**HTTP_ROUTE のトークンファイルの形式と置き場所**（同ページで確認。実測とも一致）

- パス — `.well-known/aws/securityagent-domain-verification.json`。**API が返す `routePath` には先頭の `/` が付かない**（実測）。ALB の path-pattern は `/` 始まりでないと一致しないため、そのまま渡すと**ルールは作られるが永久に一致しない**
- 中身 — **生のトークンではなく JSON**。原文: 「Place the token provided by AWS Security Agent in the file using this format: `{ "tokens": ["<insert-token>"] }`」。配列なのは同じドメインを複数の Agent Space に登録したときに両方のトークンを並べられるようにするため

**検証を通せないときのバイパス経路がある**（同ページ）— 原文: 「Customers who have authorization to perform penetration testing on an endpoint but cannot complete ownership verification can request manual verification from us. Please open a customer support case to make this request.」

### awscc プロバイダのスキーマ検証（Phase 0 項目5）

2026-08-02 に `terraform providers schema -json` を **awscc v1.95.0**（`>= 1.66.0` の制約で解決）に対して実行し、スキーマ本体を直接検査した。リソース総数 1434。

**計画が前提にしていた3つは実在する。**

| リソース名 | 結果 |
|---|---|
| `awscc_devopsagent_agent_space` | ✅ 実在 |
| `awscc_devopsagent_association` | ✅ 実在 |
| `awscc_securityagent_agent_space` | ✅ 実在 |

→ [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) の作り直しリスクは消滅した。

**計画に書かれていなかったが実在するリソース**（いずれもスキーマで確認）

`awscc_devopsagent_service` / `awscc_devopsagent_private_connection` / `awscc_securityagent_application` / `awscc_securityagent_pentest` / `awscc_securityagent_target_domain` / `awscc_securityagent_security_requirement_pack`

**スキーマから判明した、計画の記述より細かい事実**

- **`awscc_devopsagent_association` は `service_id` が必須。** AWS アカウントの紐付けでは**リテラル文字列 `"aws"`** を渡す（AWS 公式サンプル `devops-agent.tf` で確認）。`account_type` は `"monitor"`（自アカウント監視）と `"source"`（クロスアカウント）
- **Agent Space 用と Operator App 用で IAM ロールが2つ要る。** 前者は managed policy `AIDevOpsAgentAccessPolicy` ＋ Resource Explorer のサービスリンクロール作成を許す inline policy、後者は `AIDevOpsOperatorAppAccessPolicy`。信頼するのは `aidevops.amazonaws.com`（Operator App 側は `sts:AssumeRole` に加え `sts:TagSession` も要る）
- **IAM 伝播待ちが要る。** 公式サンプルは IAM ロール作成と Agent Space 作成の間に `time_sleep` 30秒を挟んでいる。Agent Space 作成時に Operator App ロールの信頼ポリシーが検証されるため、伝播前だと失敗する
- **`awscc_securityagent_target_domain` は `verification_details` を computed 属性として返す** — `http_route.route_path`（「Route path where verification token should be placed」）と `http_route.token` が Terraform から読める
- **`awscc_securityagent_agent_space` は GitHub リポジトリ接続を属性として持つ** — `integrated_resources.provider_resources.git_hub_repository{owner,name}` と `git_hub_capabilities{leave_comments, remediate_code}`。`remediate_code` の説明は「Enables creation of pull requests with automated fixes」。加えて `code_review_settings{controls_scanning, general_purpose_scanning}` がある
- **DevOps Agent 側の GitHub 連携は Terraform で完結しない。** `awscc_devopsagent_service.service_details` には `git_lab` はあるが **`git_hub` が無い**。公式 Terraform ガイドの対応連携一覧も Dynatrace / ServiceNow / Splunk / New Relic / **GitLab** / PagerDuty のみで **GitHub を含まない**。一方 `awscc_devopsagent_association.configuration` には `git_hub{owner, owner_type, repo_id, repo_name}` がある
  → **未確認**: ブラウザで GitHub App を登録した後に得られる service_id を association に渡せば Terraform 化できるのか、それとも紐付けまでコンソール操作なのか。[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) の実機で確認する

### ローカル環境

`terraform 1.13.0` / `aws-cli 2.35.22` / `node v22.19.0` / `npm 11.13.0` / `docker 28.3.3` / `gh 2.90.0` / `git 2.39.5` / `python3 3.13.7`
pnpm・bun は**無し**。

**AWS 認証情報の実状（2026-08-02 に実測）**

| profile | アカウント | 状態 |
|---|---|---|
| `default` | <既存メンバー A>（IAM ユーザー） | **アクセスキーが失効している**（`InvalidClientTokenId`）。使えない |
| `<別アカウントのプロファイル>` | <既存メンバー B>（IAM ユーザー） | 有効。メンバーアカウントなので `DescribeOrganization` は通るが `CreateAccount` 等の管理アカウント専用 API は届かない |
| `devopsagent` | 308513050613（デモアカウント） | [D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) で新設。`aws login` 済み（`arn:aws:iam::308513050613:root`）。`aws configure list` の TYPE が `login` であることを確認済み |
| `devopsagent-tf` | 同上 | Terraform 用。`credential_process` で `devopsagent` から認証情報を受け取る。**S3 バックエンドを使うときはこちら**（下記参照） |

**`aws login` と Terraform の相性（一次ソースで確認済み）**

- `aws login` は aws-cli **2.32.0 以降**の機能。短期認証情報とリフレッシュトークンを `~/.aws/login/cache` に置き、最大12時間まで自動更新する。長期アクセスキーもルート認証情報もローカルに残らない
- **共有認証情報ファイル（`~/.aws/credentials`）の静的キーは login 認証情報より優先される。** 公式トラブルシューティングに明記。`default` に失効キーが残っているため、**login には別プロファイル名を使う必要がある**
- **Terraform AWS プロバイダは `aws login` に対応している** — 2026-08-03 に**実測**。`AWS_PROFILE=devopsagent terraform apply` が通り `aws_caller_identity` が `308513050613` を返した（hashicorp/terraform-provider-aws#45316 でメンテナが 6.23.0 以降での動作を確認しているのと一致）
- **S3 バックエンドは対応していない** — 2026-08-03 に**実測で再現**。同じプロファイルで `backend "s3"` を書くと `terraform init` が落ちる。

  ```
  Error: No valid credential sources found
  Error: failed to refresh cached credentials, no EC2 IMDS role found,
  operation error ec2imds: GetMetadata, request canceled, context deadline exceeded
  ```

  S3 バックエンドは `terraform` バイナリに組み込まれておりプロバイダとは別物であるため。hashicorp/terraform#37976 で追跡され 2026-01-20 に close されたが、**ローカルの Terraform 1.13.0 では未解決**（報告は 1.14.1 に対するもので、それより古い 1.13.0 が直っている道理は無い）
- **回避策 `credential_process` は有効。これも実測で確認した** — AWS 公式が案内する方式。設定後に `terraform init` と `apply` が通り、**state が S3 に書き込まれるところまで確認済み**

**⚠️ `credential_process` には絶対パスが必要（この環境固有の落とし穴）**

`/usr/local/bin/aws` は **macOS 上に置かれた Linux 用 ELF バイナリ**（`ELF 64-bit LSB executable, x86-64 ... for GNU/Linux`）で、**実行できない**。実際に動いているのは Homebrew 版の `/opt/homebrew/bin/aws`（aws-cli 2.35.22）。

`credential_process` は `sh` 経由で実行されるため、コマンド名を `aws` と書くと壊れた方に当たる。

```
sh: /usr/local/bin/aws: cannot execute binary file
Error: failed to refresh cached credentials, process provider error:
error in credential_process: exit status 126
```

→ **`credential_process` には `/opt/homebrew/bin/aws` と絶対パスで書く。** [D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) の設定例はこの形になっている。
なおこの壊れたバイナリは `aws` を `sh` や `env` 経由で起動する**あらゆるツールを壊しうる**ので、いずれ削除しておくのが望ましい。

### DevOps Agent と Security Agent の役割分担

AWS のフロンティアエージェントは2つあり、守備範囲が分かれている。

| | 担当フェーズ | やること |
|---|---|---|
| **Security Agent** | 設計・レビュー | 脅威モデリング、コードスキャン、脆弱性検出、自律ペネトレーションテスト。GitHub の PR を検知し脆弱性を PR コメントで指摘 |
| **DevOps Agent** | リリース・運用・改善 | 自律インシデント対応（アラート起点で調査し根本原因を特定）、予防レコメンデーション、アプリケーショントポロジー、SRE タスク自動化 |

**脆弱性の検出そのものは Security Agent の担当であり、DevOps Agent の機能ではない。** ただし AWS 公式に「Add security context to operational investigations with AWS DevOps Agent and Wiz」があり、**セキュリティ起因の事象を運用インシデントとして調査する**のは DevOps Agent の範囲内。

### AWS Organizations

2026-08-02 に `aws organizations describe-organization` を 別アカウントのプロファイルから実行して再確認した（メンバーアカウントからでも組織の基本情報は読める）。

| 項目 | 値 |
|---|---|
| 組織 ID | `o-xxxxxxxxxx` |
| 管理アカウント | **<管理アカウント ID>**（ルートのメールアドレスは伏せる。[D-022](#d-022-メールアドレスはリポジトリに置かない) 参照） |
| FeatureSet | `ALL` |
| 既存メンバー | <既存メンバー A>、<既存メンバー B>（どちらも本プロジェクトと無関係） |
| **デモアカウント** | **308513050613** — [D-003](#d-003-専用の新規-aws-アカウントを発行する) の専用アカウント。**発行済み** |
| SCP | **ENABLED** — 新アカウントは OU/ルートの SCP を継承する |

### Phase 0 の実機確認結果（デモアカウント 308513050613）

2026-08-03 に `aws login` したセッションから実際に API を叩いて確認した。すべて実測値であり、推測は含まない。

**アカウントの状態** — Phase 0 の確認時点では S3 バケット 0 / ECS クラスタ 0 / DynamoDB テーブル 0 / ALB 0 / Agent Space 0（DevOps・Security とも）。
[D-003](#d-003-専用の新規-aws-アカウントを発行する) の「既存リソースがゼロ」という前提は成立していた。

> **その後 2026-08-03 に Security Agent をコンソールから有効化したため、現在はゼロではない。** 下の「Security Agent の実状」を参照。

**ルートユーザーの MFA** — 有効（`iam:GetAccountSummary` の `AccountMFAEnabled = 1`）。[D-018](#d-018-terraform-はルートユーザーのまま回す) が要求していた条件を満たしている。

**Security Agent の実状（2026-08-03 にコンソールで有効化）**

| 項目 | 値 |
|---|---|
| Application | `app-966a2407-…`（名前 `SecurityAgent`） |
| Agent Space | `as-d363b56d-…`（名前 **`SandboxAgent`**）、`ap-northeast-1`、作成 2026-08-03T04:52:20Z |
| Target Domain | 未登録（`targetDomainIds: []`） |
| ウェブアプリ URL | `app-<id>.securityagent.global.app.aws` |

**コンソール上の各機能の状態**（スクリーンショットで確認）

| 機能 | 状態 |
|---|---|
| ペネトレーションテスト | セットアップが必要 |
| 設計レビュー **（プレビュー）** | 準備完了 |
| 脅威モデル **（プレビュー）** | セットアップが必要 |
| コードレビュー **（プレビュー）** | セットアップが必要 |

> **コードレビューは preview 扱いである。** [D-006](#d-006-security-agent-も併せて導入する) と [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の項目10（PR にコードレビューコメントが付くこと）はこの機能に依存する。GA ではないため挙動が変わりうる。

**ウェブアプリへのユーザーアクセスは IAM Identity Center が管理する** — コンソールに「ウェブアプリへのユーザーアクセスは、IAM アイデンティティセンターによって管理されます」と表示される。
ただし**管理者アクセスは IdC のユーザー割り当てなしで利用できる**（同画面の「管理者アクセス」ボタン）ため、[D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) で IdC を却下した判断は覆らない。運用者を増やしたくなったときだけ IdC が必要になる。

**SCP による制限（項目3）— 弾かれていない**

判定方法の妥当性は公式ドキュメント [Service control policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html) で裏を取った。原文: 「SCPs affect all users and roles in attached accounts, **including the root user**」「An SCP restricts permissions for IAM users and roles in member accounts, **including the member account's root user**」。
例外リスト（管理アカウントの操作・サービスリンクロール・Enterprise サポート登録・CloudFront trusted signer・Lightsail/EC2 の逆引き DNS・Alexa/Mechanical Turk 等）に本プロジェクトのサービスは含まれない。
→ **メンバーアカウントの root で実効権限を見れば SCP の影響を判定できる。** かつ root は IAM ポリシーによる制限を受けないため、`AccessDenied` が返ればそれは SCP 由来と考えてよい。

**読み取り系**

| API | 結果 |
|---|---|
| `ecs:ListClusters` | ✅ |
| `elasticloadbalancing:DescribeLoadBalancers` | ✅ |
| `dynamodb:ListTables` | ✅ |
| `aidevops`（`devops-agent list-agent-spaces` / `list-services`） | ✅ |
| `securityagent`（`securityagent list-agent-spaces`） | ✅ |
| `ec2:DescribeVpcs` / `iam:ListRoles` / `s3:ListBuckets` / `ecr:DescribeRepositories` / `logs:DescribeLogGroups` / `cloudtrail:DescribeTrails` / `servicequotas:ListServices` | ✅ |

**作成系 — 読み取りの結果からは推論できないので、個別に測った**

> **外部レビューでの指摘を受けて追加した。** 以前この節は「S3 の作成・削除が通ったから書き込みも通る」と書いていたが、
> **SCP は Action 単位で拒否できる**ため、`ecs:ListClusters` を許可しつつ `ecs:CreateCluster` を拒否する SCP は成立しうる。
> S3 の成功を他サービスに一般化するのは誤りだった。以下は各アクションを実際に叩いた結果である。

| 検証方法 | API | 結果 |
|---|---|---|
| **実際に作成 → 削除** | `ecs:CreateCluster` | ✅ 成功 |
| **実際に作成 → 削除** | `dynamodb:CreateTable` | ✅ 成功 |
| **実際に作成 → 削除** | `ecr:CreateRepository` | ✅ 成功 |
| **実際に作成 → 削除** | `iam:CreateRole` | ✅ 成功 |
| **実際に作成 → 削除** | `logs:CreateLogGroup` | ✅ 成功 |
| **実際に作成 → 削除** | `s3:CreateBucket` ＋ Terraform apply（state 書き込み） | ✅ 成功 |
| **実際に作成 → 削除** | `awscc_logs_log_group`（awscc プロバイダ経由） | ✅ 成功 |
| 無効パラメータで認可のみ | `elasticloadbalancing:CreateLoadBalancer` | ✅ 認可通過（パラメータ検証で停止） |
| 無効パラメータで認可のみ | `aidevops:CreateAgentSpace` | ✅ 認可通過 |
| 無効パラメータで認可のみ | `securityagent:CreateTargetDomain` | ✅ 認可通過 |
| 無効パラメータで認可のみ | `cloudtrail:CreateTrail` | ✅ 認可通過（`S3BucketDoesNotExistException` まで到達） |
| 無効パラメータで認可のみ | `budgets:CreateBudget` | ✅ 認可通過 |
| 無効パラメータで認可のみ | `ec2:CreateVpc` | ✅ 認可通過 |

**「無効パラメータで認可のみ」の判定基準** — SCP による拒否は `AccessDeniedException` として返る。
`ValidationException` 等のパラメータエラーが返るということは、**認可を通過してパラメータ検証まで進んだ**ということ。
ただし**サービスによっては認可より先にパラメータを検証する**可能性があるため、この方法の証拠力は「実際に作成」より弱い。
`AccessDenied` が返らなかったことは確実だが、それを「確実に許可されている」と読むのは行き過ぎである。

**作成したリソースはすべて削除済み**で、アカウントは空の状態に戻してある。

**唯一弾かれた API** — `devops-agent get-account-usage` が `AccessDeniedException: Access denied`（ap-northeast-1 / us-east-1 の両方）。
同じ `aidevops` 名前空間の `list-agent-spaces` と `list-services` は通るため、**名前空間まるごとを denyする SCP ではない。** 原因は未特定（下記「未確認」を参照）。

**クォータ（項目4）— 足りている**

| クォータ | 値 | 必要量 |
|---|---|---|
| **Fargate On-Demand vCPU resource count** | **6** | **0.5**（0.25 vCPU × desired 2、[D-013](#d-013-委任された技術判断こちらで決定)） |
| Fargate Spot vCPU resource count | 6 | 未使用 |
| Fargate On-Demand Burst Launch Rate | 100 | — |
| Application Load Balancers per Region | 50 | 1 |

**コストデータの可視性（項目7）— 見える**

`ce:GetCostAndUsage` をデモアカウントから実行し、正常なレスポンス（`ResultsByTime` / `Estimated: true`）が返った。金額は $0 だが、これは**アカウントが新品で支出が無いため**であり、API 自体は機能している。
権限が無ければ `AccessDeniedException` が返るはずなので、**Cost Explorer のリンクアカウントアクセスは有効**と判断してよい。
→ ただし「実際に課金が発生したときに金額が乗ってくるか」は支出ゼロの現時点では確かめようがない。**[Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) 以降に再確認する。**

**Security Agent の無料トライアル残枠（項目6）— 🚧 未確認のまま**

CLI からは取得できなかった。試したもの:

- `aws devops-agent get-account-usage` → `AccessDeniedException`
- `aws securityagent` に使用量・トライアル系の API が**存在しない**（`create-membership` / `list-memberships` はあるが用途が異なる）
- `aws freetier get-free-tier-usage` → `{"freeTierUsages": []}`（空）

→ **コンソールで確認するしかない可能性が高い。** [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) はペンテスト実行直前の再確認を要求しており、そこで必ず見ることになる。
**ペンテストは $50/task-hour で予算上限 $100（[D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ)）の半分を1回で消費しうるため、残枠が読めないまま実行してはいけない。**

### Phase 1 の実機確認結果（2026-08-03）

`terraform/bootstrap/` の apply とその前後で実際に測った値。すべて実測であり、推測は含まない。

**解決されたプロバイダ** — `hashicorp/aws` **v6.57.1**（`>= 6.23.0` の制約で解決）。`.terraform.lock.hcl` に固定して commit した。

**apply で作られたもの（14 リソース）** — S3 バケット2つ（state / CloudTrail 証跡）、GitHub OIDC プロバイダ、IAM ロール＋`AdministratorAccess` のアタッチ、ECR リポジトリ、CloudTrail、AWS Budgets、および S3 の付随設定（バージョニング・暗号化・パブリックアクセスブロック・バケットポリシー）。

| 項目 | 実測結果 |
|---|---|
| **IAM ロールの `description` に日本語を書くと落ちる** | `CreateRole` が `ValidationError: Value at 'description' failed to satisfy constraint: Member must satisfy regular expression pattern: [\u0009\u000A\u000D\u0020-\u007E\u00A1-\u00FF]*` を返した。**ASCII 印字可能文字と Latin-1 補助しか通らない。** リソース名やタグ値ではなく `description` 固有の制約。→ 英語に書き換えて解決 |
| **`aws_iam_openid_connect_provider` に `thumbprint_list` は不要** | 省略したまま `validate` と `apply` が通った（aws プロバイダ v6.57.1）。GitHub の OIDC は AWS 側が自前の信頼済み CA で TLS を検証するため、指定しても使われない |
| **Budgets は ap-northeast-1 のプロバイダのまま作成できた** | us-east-1 のエイリアスプロバイダを足さずに `aws_budgets_budget` の作成が成功した。SDK がグローバルエンドポイントへ自動解決する。**作成に約10秒かかる**（他リソースは1秒） |
| **CloudTrail のバケットポリシーは `s3:x-amz-acl` 条件を今も要求する** | [Amazon S3 bucket policy for CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-s3-bucket-policy-for-cloudtrail.html) を 2026-08-03 に直接確認。`aws:SourceArn`（trail の ARN）と併記する。**バケットポリシーと trail は相互参照になる**ため、trail ARN は文字列で組み立てて循環を切る |
| **CloudTrail は配信まで通っている** | `get-trail-status` の `LatestDeliveryTime` に値が入り、証跡バケットに実際のオブジェクト（`AWSLogs/<account>/CloudTrail/ap-northeast-1/…json.gz` と `us-east-1/…`）が並んでいることを確認した。**`LatestDeliveryError: null` だけでは判定しない** — 配信を1度も試みていない段階でも null になるため。multi-region 設定が効いていることも、us-east-1 のオブジェクトが出ていることで確認できる |
| **信頼ポリシーの `sub` 限定が効いている** | `iam get-role` で `StringLike: {"token.actions.githubusercontent.com:sub": "repo:OR-Sasaki/devops-agent-form:*"}` と `StringEquals: {"...:aud": "sts.amazonaws.com"}` を確認 |

**`terraform plan` は S3 に書き込む（`use_lockfile = true` の場合）**

[Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) の完了条件「state を読み書きできる」を `init` と `plan` だけで判定してよいかを確かめるため、`TF_LOG=TRACE` で実測した。

```
rpc.method=PutObject    aws.s3.key=main/terraform.tfstate.tflock   http.status_code=200
rpc.method=GetObject    aws.s3.key=main/terraform.tfstate.tflock   http.status_code=200
rpc.method=DeleteObject aws.s3.key=main/terraform.tfstate.tflock   http.status_code=204
```

→ **`plan` はロックオブジェクトを PutObject して DeleteObject する。** 書き込み権限が無ければ「Error acquiring the state lock」で落ちる。
したがって **CI で `plan` が通れば読みだけでなく書きも通っている**と言ってよい。`apply` を待つ必要はない。

**ローカルからの S3 バックエンド疎通** — `AWS_PROFILE=devopsagent-tf` で `terraform/main/` の `init` と `plan` が通った。[D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) の `credential_process` 方式が Phase 1 の構成でも成立することを再確認した。

**GitHub リポジトリと CI（2026-08-03）**

| 項目 | 実測値 |
|---|---|
| リポジトリ | `OR-Sasaki/devops-agent-form`（Public） |
| リポジトリ ID / オーナー ID | `1321456466` / `15667196`（`gh api` で取得。どちらも公開 API から誰でも読める） |
| ランナー | `ubuntu-latest`。**AWS CLI 2.36.2 がプリインストール済み**（[runner-images](https://github.com/actions/runner-images) の Ubuntu2404-Readme を確認）なので、疎通確認に別途インストールが要らない |
| action の版 | `actions/checkout` v7.0.1 / `aws-actions/configure-aws-credentials` v6.2.3 / `hashicorp/setup-terraform` v4.0.1。いずれも完全長 SHA で固定（[D-024](#d-024-サードパーティ-action-は完全長のコミット-sha-で固定する)） |

**OIDC の `sub` は不変形式が発行されている（実測で確定）**

信頼ポリシーを**不変形式1件だけ**に絞った状態（[D-023](#d-023-oidc-の信頼ポリシーは不変形式の-sub-に切り替える)）で、初回のワークフロー実行が成功した。
**旧形式を一切許可していないので、成功したこと自体が「不変形式が発行されている」ことの証拠になる。**
2026-07-15 以降に作成されたリポジトリに関する公式ドキュメントの記述が、このリポジトリで実際に成立していることを確認できた。

```
Assuming role with OIDC
Authenticated as assumedRoleId AROAUPVGPR723GUOXFF77:gha-30797407173
OIDC assume: OK
Terraform has been successfully initialized!
No changes. Your infrastructure matches the configuration.
```

**「state を書ける」の根拠は2段構えである（推論の部分を明示する）**

1. **実測** — `use_lockfile = true` の `plan` が `.tflock` を PutObject / GetObject / DeleteObject することを、ローカルで `TF_LOG=TRACE` により確認した（上記）
2. **推論** — CI の `plan` が成功した以上、CI のロールでもその3操作が通っている。書き込み権限が無ければ「Error acquiring the state lock」で停止するため

**CI から S3 への PutObject 自体を直接観測してはいない。** CloudTrail は管理イベントのみで、S3 のデータイベントは有効にしていないため（有効にすると課金対象になる）。
`terraform/main/` に実リソースが入る [Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の初回 apply で、state ファイルそのものが S3 に書かれることを直接確認できる。

### Phase 2 の実機確認結果（2026-08-03）

`terraform/main/` を書く過程で実際に測った値。すべて実測であり、推測は含まない。

**解決されたプロバイダ** — `hashicorp/aws` **v6.57.1** ／ `hashicorp/awscc` **v1.95.0** ／ `hashicorp/time` **v0.14.0**。
awscc は [Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) のスキーマ検証と**同じ v1.95.0 に解決した**ため、あの検証結果はそのまま有効である。`.terraform.lock.hcl` に固定して commit した。

**完了条件の達成** — `AWS_PROFILE=devopsagent-tf` で `terraform plan` が通り、**45 リソースの作成計画**が出た。`terraform fmt -check -recursive` と `terraform validate` も通っている。
[D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) の `credential_process` 方式が、実リソースを含む構成でも成立することを確認した。

**awscc のスキーマで、Phase 0 の記録より細かく判明したこと**

| 対象 | 実測結果 |
|---|---|
| `awscc_securityagent_agent_space.aws_resources.vpcs` | **単一オブジェクトではなくリスト**（`NESTING=list`）。単一オブジェクトで書くと `validate` が `list of object required` で落ちる |
| `awscc_devopsagent_association.configuration.git_hub.owner_type` | 許容値は **`"organization"` / `"user"` の小文字2値**。`"User"` と書くと `Invalid Attribute Value Match` で落ちる |
| `awscc_devopsagent_agent_space.tags` | `NESTING=set`。`awscc_securityagent_agent_space.tags` は `NESTING=list`。**同じ `tags` でも型が違う** |
| awscc プロバイダの `default_tags` | **存在しない。** aws プロバイダと違い、タグは各リソースに明示的に書く必要がある |
| `awscc_securityagent_agent_space` の IAM 属性 | **無い。** Agent Space 側から app role / service role を指定する口は存在しない |

**AWS マネージドポリシーの ARN（実在を `iam get-policy` で確認）**

| ポリシー | ARN |
|---|---|
| `AIDevOpsAgentAccessPolicy` | `arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy` |
| `AIDevOpsOperatorAppAccessPolicy` | `arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy` |
| `AmazonECSTaskExecutionRolePolicy` | **`arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy`** |

> **ECS のものだけ `service-role/` 配下にある。** `service-role` を落とした ARN は `NoSuchEntity` になることを実際に確認した。
> **これは plan では検出できない**（ARN は文字列として扱われる）ので、apply まで発覚しない種類の誤りである。

**アカウントの現状（`iam list-roles` / `securityagent list-agent-spaces` で確認）**

- **Security Agent の Agent Space `SandboxAgent` は削除済み。** `list-agent-spaces` が `{"agentSpaceSummaries": []}` を返した。[D-019](#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる) の手作業は完了しており、[Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の初回 apply で名前が衝突する余地は無い
- **Application 側の IAM ロールは `application-<timestamp>` という名前で既に存在する**（実値の末尾は伏せる。[D-022](#d-022-メールアドレスはリポジトリに置かない)）。`AWSSecurityAgentWebAppPolicy` がアタッチされ、`securityagent.amazonaws.com` を信頼している。
  計画が書いていた `SecurityAgentAppRole-*` という名前ではなく、**コンソールが `application-<timestamp>` 形式で作っていた。**
  → Terraform で同名を作る危険は無いが、**この既存ロールを Terraform で管理してはいけない**（[D-019](#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる) の Application と同じ理由で二重管理になる）
- `AWSServiceRoleForResourceExplorer` が**既に存在する**。DevOps Agent の Agent Space ロールに与える `iam:CreateServiceLinkedRole` は、それでも公式サンプル通り残してある（作成済みなら何もしない権限であり、外す理由が無い）

**CloudWatch メトリクスについて公式ドキュメントで確認した事実**

| 項目 | 確認内容 |
|---|---|
| 算術演算子の欠損値 | **「Missing values in a time series are treated as 0」**（[Metric math](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/using-metric-math.html)）。→ `m1+m2` なら片方が欠損してももう片方の値が出る。ALB の 5xx は片方だけ報告される状況が普通に起きるため、この性質に依存している |
| `HTTPCode_ELB_5XX_Count` | Reporting criteria は **「There is a nonzero value」**。5xx が出ていなければメトリクス自体が存在しない |
| `HTTPCode_Target_5XX_Count` / `UnHealthyHostCount` | Reporting criteria は **「Reported if there are registered targets」** |
| `TargetResponseTime` | **「The most useful statistics are `Average` and `pNN.NN` (percentiles)」** → p95 は正しい使い方 |
| `UnHealthyHostCount` の統計 | AWS が **`Minimum` を推奨**している（[D-028](#d-028-異常ホストアラームは-minimum-統計で見る) に原文を引用） |
| ECS の `containerInsights` | 有効値は **`enhanced` / `enabled` / `disabled`** の3つ（[ClusterSetting](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ClusterSetting.html)）。本構成は `enhanced` |
| DynamoDB の `ThrottledRequests` | ディメンションは **`TableName, Operation`**。[D-031](#d-031-dynamodb-のスロットリング監視は-throttleevents-で行う) でメトリクスごと差し替えた |

**Cost Explorer — 🚧 まだ「課金が乗る」ことの確認にはなっていない**

`ce:GetCostAndUsage`（2026-07-01〜2026-08-04、SERVICE 別）を実行し、**正常なレスポンスが返った**。ただし金額は 7月・8月とも `"0"` で `Groups` は空だった。

> **これを「コストデータが見えない」とも「見える」とも読んではいけない。**
> [Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) のリソースを作ったのは **2026-08-03（当日）**であり、
> ①Cost Explorer の反映には遅延がある ②CloudTrail の証跡1本目は管理イベントなら無料で、S3 も数 MB なので**そもそも請求額がほぼゼロ**、
> という2つの理由から、**$0 が返ること自体は正常な構成でも起こる。**
> 判定にはインフラが実際に稼働した後の日次実績が要る。**[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の項目11 が本来の確認点である。**

### Phase 3・4 の実機確認結果（2026-08-03）

**`terraform/main/` の初回 apply が成功した。** [run 30810215552](https://github.com/OR-Sasaki/devops-agent-form/actions/runs/30810215552)。すべて実測であり、推測は含まない。

**所要時間** — ジョブ全体で **6分15秒**。

| ステップ | 所要 |
|---|---|
| `docker build` ＋ `docker push`（初回・キャッシュ無し） | 33 秒 |
| `terraform apply`（**48 リソース**を新規作成） | **3分36秒** |
| `aws ecs wait services-stable` | 1分24秒 |

計画は「ALB の作成だけで3〜5分」を見込んでいたが、**apply 全体が 3分36秒で終わった。** `time_sleep` 30 秒と Agent Space 2つを含んだうえでこの値である。
ジョブのタイムアウトを 45 分に取ったのは過剰だったが、**壊れたときに諦めるまでの時間**（`services-stable` の約10分）を含むので、この余裕は残す。

**2回目のデプロイ（更新経路）も確認した** — [run 30810870748](https://github.com/OR-Sasaki/devops-agent-form/actions/runs/30810870748)。

| ステップ | 初回（新規作成） | 2回目（更新） |
|---|---|---|
| `terraform apply` | 3分36秒（48 リソース作成） | **21 秒**（タスク定義の新リビジョン＋サービス更新のみ） |
| `services-stable` の待ち | 1分24秒 | **3分12秒**（ローリング更新で入れ替えるぶん長い） |

**ローリング更新中も無停止だった。** 入れ替えの最中に `GET /healthz` を10回連続で叩き、**非 200 が0回**。
`deployment_minimum_healthy_percent = 100` / `deployment_maximum_percent = 200` が意図通り効いており、
更新中は一時的に `runningCount = 3` になる（旧2台＋新1台）。
更新後、ALB が返す `commitSha` が新しいコミットに切り替わることも確認した。

> **「デプロイ = `terraform apply`」（[D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)）が、作成だけでなく更新でも成立している。**
> 観点1（AWS 設定起因）と観点2（コード起因）が同じ1本のデプロイイベントとして見える、という RCA デモの前提が実際に揃った。

**awscc の3リソースは初回 apply で問題なく作られた** — 最も検証が薄いと見ていた部分だが、`plan` から `apply` まで追加の修正は不要だった。

| リソース | 実測 |
|---|---|
| `awscc_devopsagent_agent_space` | ✅ 作成（`devops-agent-form`） |
| `awscc_devopsagent_association`（`service_id = "aws"`） | ✅ 作成 |
| `awscc_securityagent_agent_space` | ✅ 作成（`devops-agent-form`）。[D-019](#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる) の通り名前の衝突は起きなかった |

**ECS タスクは2台とも起動した（[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) 項目1 に相当）**

- `runningCount = 2` / `rolloutState = COMPLETED`
- 2台が **`ap-northeast-1a` と `ap-northeast-1c` に分かれた**（[D-013](#d-013-委任された技術判断こちらで決定) の AZ 冗長が実際に効いている）
- `ecs.cpu-architecture` は**両方 `x86_64`**。`runtime_platform` の指定と CI のビルドが一致している
- ALB のターゲットは**2つとも `healthy`**
- **`assign_public_ip = true` は効いている。** ECR の pull と CloudWatch Logs への到達がどちらも成功しており、NAT 無し構成が成立することを実測で確認した

> **CI が push したイメージは単一プラットフォームの Docker v2 マニフェストだった**（`application/vnd.docker.distribution.manifest.v2+json`）。
> ローカルの Docker Desktop で焼くと attestation 付きの OCI インデックスになるが、`ubuntu-latest` の classic builder は素の単一マニフェストを吐く。**ECS はそのまま pull できた。**

**アプリの疎通（[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) 項目2・7 に相当）**

- `GET /healthz` が `{"status":"ok","commitSha":"eedb72c…"}` を返す
- `POST /submit` → **DynamoDB に項目が入る。** `commitSha` 属性にデプロイの SHA が入っていることも確認した
- `GET /admin` は**認証情報なしで 401、正しい認証情報で 200**（[D-035](#d-035-ベースラインには観点3-の故障を1つも置かない)）。SSM Parameter Store からの `ADMIN_PASSWORD` 注入が機能している
- **XSS の余地は塞がっている。** `<script>alert(1)</script>` を含む本文を送信し、`/admin` の HTML に `&lt;script&gt;` としてのみ現れ、**生の `<script>` が 0 件**であることを確認した

**構造化ログは CloudWatch 側で JSON として解析されている（[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) 項目7 の前提）**

```
aws logs filter-log-events --log-group-name /ecs/devops-agent-form \
  --filter-pattern '{ $.commitSha = "eedb72c0d99cc1f8086af2b29703073a226698ee" }'
```

**このメトリクスフィルタ構文（`$.commitSha`）で実際にヒットした。** つまりログは文字列としてではなく
**JSON として解析されており、`commitSha` をフィールドとして絞り込める。**
「アラーム → ログ（SHA）→ タスク定義（イメージタグ）→ コミット」の相関経路が成立する条件が揃った。

ログには `requestId` に加えて **ALB が付ける `X-Amzn-Trace-Id`（`traceId`）** と、`X-Forwarded-For` の**末尾**から取った接続元 IP が乗る。

**⚠️ `UnHealthyHostCount` アラームは、作成直後に ALARM へ落ちた** — [D-028](#d-028-異常ホストアラームは-minimum-統計で見る) が代償として引き受けた挙動が**実際に起きた。**

```
devops-agent-form-alb-unhealthy-hosts   ALARM
  Threshold Crossed: no datapoints were received for 2 periods
  and 2 missing datapoints were treated as [Breaching].
```

**このときターゲットは2つとも `healthy` である。** 障害ではなく、**トラフィックがゼロでメトリクスが報告されていない**ことによる。
[D-028](#d-028-異常ホストアラームは-minimum-統計で見る) は「静かなときに鳴る」を文書からの**予測**として書いていたが、**予測ではなく実際の挙動だと確定した。**
残る6つのアラームは `notBreaching` なのですべて `OK`。

**そして疎通確認でリクエストを流した直後、このアラームは `OK` に戻った。**

```
Threshold Crossed: 1 datapoint [0.0 (03/08/26 11:42:00)] was not greater than
or equal to the threshold (1.0) and 1 missing datapoint was treated as [Breaching].
```

→ **このアラームはトラフィックの有無で ALARM と OK を往復する。** 一方向に落ちたままになるのではない。

> **デモ時の読み方に影響する。** このアラームが ALARM でも、それ単体では異常を意味しない。
> **「直近にトラフィックがあったか」を先に確認しないと、状態を読み違える。**
> [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の項目4 で閾値を見直すか、`treat_missing_data` を選び直すかを判断する。
> **「全滅を無音にしない」ことと引き換えなので、単純に `notBreaching` へ戻すのは [D-028](#d-028-異常ホストアラームは-minimum-統計で見る) の判断を覆すことになる。**

**サービスの `MemoryUtilization` は 1.3% → 4.9% で推移した**（Container Insights が `enhanced`）。健全時の値であり、閾値 80% までは十分に距離がある。

### Phase 5・6 の実機確認結果（2026-08-03）

すべて実測であり、推測は含まない。

**`UnHealthyHostCount` が ALARM に落ちた原因は、トラフィックの有無ではなかった（前回の解釈を訂正する）**

[Phase 3・4 の実機確認結果](#phase-34-の実機確認結果2026-08-03) は「このアラームはトラフィックの有無で ALARM と OK を往復する」と書いていたが、**これは誤った一般化だった。**

| 時刻 (UTC) | 観測 |
|---|---|
| 11:39・11:40 | `UnHealthyHostCount` の **datapoint が存在しない** |
| 11:41:41 | 2 missing datapoints → `breaching` 扱いで **ALARM** |
| **11:42 以降** | **毎分 `0.0` が途切れず報告される**（48/48 datapoint） |
| 11:45:41 | **OK** に復帰 |
| 12:00〜12:25 | **`RequestCount` が 0 のまま。それでもアラームは OK のまま** |

→ **メトリクスが欠けていたのは「登録ターゲットがまだ無い」ALB 作成中の数分間だけである。**
これは公式の Reporting criteria **「Reported if there are registered targets」**とそのまま一致する。
[D-028](#d-028-異常ホストアラームは-minimum-統計で見る) が代償として引き受けた「静かな時間帯に鳴る」は、**少なくとも本構成では発生していない**（同ページの「only when requests are flowing through the load balancer」は、この指標の実挙動とは一致しなかった）。

> **観測窓は約1時間である。** 「二度と鳴らない」と言えるだけの長さではないが、
> **「トラフィックが無いと鳴る」という因果は、25分間の無トラフィックで鳴らなかったことで否定できる。**
> 判断は [D-039](#d-039-unhealthyhostcount-は-breaching-のまま維持する) を参照。

**CloudTrail に「誰が・いつ・何を」が揃っている（[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) 項目5）**

`UpdateService` の記録を1件そのまま読んだ結果:

| 項目 | 値 |
|---|---|
| `userIdentity.arn` | `arn:aws:sts::308513050613:assumed-role/devops-agent-form-github-actions/`**`gha-30811804110`** |
| `userAgent` | `… Terraform/1.13.0 … terraform-provider-aws/6.57.1 …` |
| `requestParameters.taskDefinition` | `…:task-definition/devops-agent-form:4` |

> **セッション名が `gha-<GitHub Actions の run_id>` になっているため、CloudTrail の1レコードから Actions の実行、さらにコミットまで一意に辿れる。**
> [観点2](./01-fault-perspectives.md#観点2-アプリコード起因) の相関経路（アラーム → ログ → タスク定義 → コミット）とは**独立した2本目の経路**であり、観点1（AWS 設定起因）ではこちらが主経路になる。

**`var.fault_injection` の口は6値すべて通っている（項目6）**

`plan` のみで確認した（**故障は仕込んでいない**。[D-005](#d-005-故障は今は仕込まないただし3観点の余地を設計に残す)）。

| 値 | plan に出た変更 |
|---|---|
| `iam_denied` | `aws_iam_role_policy.ecs_task_dynamodb` を更新 |
| `bad_healthcheck` | `aws_lb_target_group.app` を更新 |
| `closed_sg` | `aws_vpc_security_group_ingress_rule.ecs_from_alb[0]` を破棄 |
| `low_memory` | `aws_ecs_task_definition.app` を置換 |
| `dynamodb_throttle` | `aws_dynamodb_table.submissions` を更新 |
| `broken_route` | `aws_route.public_default[0]` を破棄 |

不正値（`bogus`）は `variables.tf` の validation が拒否することも確認した。

**⚠️ ローカルの `terraform plan` で drift を見るときはダミーのイメージタグを使ってはいけない**

[D-032](#d-032-イメージタグは-default-を持たない必須変数にする) は「ローカルからは `-var image_tag=bootstrap`」と書いているが、
**この値で plan すると必ず 3 件の差分**（タスク定義の置換＋サービス更新）が出る。実際にデプロイ済みのイメージタグと食い違うためで、drift ではない。

```
Plan: 1 to add, 1 to change, 1 to destroy.
```

→ **`plan` が空であることを確認したいときは、実際にデプロイされているコミット SHA を渡す。**
`-var image_tag=$(git rev-parse HEAD)`（`main` が最後にデプロイされたコミットである場合）。
この値で `No changes.` になることを確認済み。

**DevOps Agent がトポロジーの土台を自前で作っていた（項目3 の前提）**

- `devops-agent get-association` が **`"status": "valid"`**、`validate-aws-associations` が**指摘ゼロ**を返す
- **Resource Explorer のインデックスが複数リージョンに自動作成されていた。** [devops-agent.tf](../../terraform/main/devops-agent.tf) が Agent Space ロールに与えた `iam:CreateServiceLinkedRole` が実際に使われたということ
- インデックスを検索すると **ALB → ECS（クラスタ・サービス・タスク定義）→ DynamoDB が揃って登録されている**（`devops-agent-form` で 35 件）

**項目8・9・10 の結果（2026-08-04）**

| 項目 | 結果 |
|---|---|
| **8 GitHub 接続** | ✅ 両方。DevOps Agent は association（`serviceId` は UUID）、Security Agent は integrated resource（`accessType: PUBLIC`） |
| **9 ターゲット検証** | ✅ **`VERIFIED`**。`gawacchi.link` を DNS_TXT で検証。`Verification successful for domain gawacchi.link. This domain can be used in pentests` |
| **10 コードレビュー** | ✅ **コメントが付いた**（[D-045](#d-045-コードレビューを見るときだけ一時的に-private-にする) の手順で一時的に private にして確認） |

**項目10 で実際に返ってきたもの** — [D-035](#d-035-ベースラインには観点3-の故障を1つも置かない) は「指摘ゼロなら `No issues identified.`」を想定していたが、
**実際には2件の指摘が返り、しかもどちらも妥当だった。**

- 解析開始時に「reviewing your pull request」のコメント（文書どおりの2段構え）
- 完了後に **`state=COMMENTED` のレビュー1件 ＋ インラインコメント2件**
- 指摘対象は**アプリではなく、その PR で書き換えた CI ワークフロー**だった

> **判定は「コメントが付くか」で行う（[D-035](#d-035-ベースラインには観点3-の故障を1つも置かない)）ので合格である。**
> 指摘内容の検証と対応は [D-047](#d-047-連携-id-は-variables-ではなく-secrets-に置く) に記録した。**1件は実測すると経路が指摘と違い、もう1件は影響が過大だった。**
> エージェントの指摘も裏取りしてから受け入れる、という原則がそのまま必要だった。

**DNS_TXT の検証値は `routePath` と違って加工が要らなかった**

| | API が返した値 | 加工 |
|---|---|---|
| HTTP_ROUTE の `routePath` | `.well-known/…`（先頭の `/` 無し） | **要**（ALB の path-pattern に合わせて `/` を足す） |
| DNS_TXT の `dnsRecordName` | `_aws_securityagent-challenge.gawacchi.link` | **不要**（そのまま Route 53 のレコード名になる） |
| DNS_TXT の `token` | `aws-securityagent-domain-verification=…` | **不要**（`aws_route53_record` が TXT の引用符を自動で付ける） |

**Route 53 の TXT レコードは、255 文字以下なら引用符を自分で書かなくてよい**（実測）。
`records = [token]` と書くと `"aws-securityagent-domain-verification=…"` として保存された。

**⚠️ Security Agent 側の可視性の認識は即座には追随しない** — public に戻した直後も
`list-integrated-resources` は `"accessType": "PRIVATE"` を返し続けた。**キャッシュされている。**
`leave_comments` を先に `false` へ戻してあるので実害は無いが、
**可視性を戻した直後に「まだ private 扱いだから」と判断してはいけない。**

**エージェントの GitHub 連携について CLI から判明したこと**

| 事実 | 根拠 |
|---|---|
| **DevOps Agent の GitHub 連携は `register-service` では登録できない** | `--service` の許容値は dynatrace / servicenow / pagerduty / gitlab / eventChannel / mcpserver 系 / azureidentity / remoteagent 系のみで、**GitHub が無い。** help に「Services that can be registered via the post-registration API (**excludes OAuth 3LO services**)」と明記されている。→ **ブラウザでの OAuth 認可が必須**という [D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) の例外は正しかった |
| **`associate-service` は GitHub を受け付ける** | `--configuration` のタグ付きユニオンに `github` があり、必須は `repoName` / `repoId` / `owner` / `ownerType`（`organization` または `user`）。**`awscc_devopsagent_association.configuration.git_hub` と同じ形** |
| **Security Agent の GitHub 認可は API から開始できる** | `securityagent initiate-provider-registration --provider GITHUB` が `redirectTo`（`https://github.com/apps/aws-security-agent/installations/new`）と `csrfState` を返す。**ただし state の渡し方は確認できていない**ので、コンソールから開始するほうが確実 |

### GitHub

ユーザー `OR-Sasaki`（org 無し、public repo 27）。`gh` の token scope に `repo` と `workflow` あり → リポジトリ作成も Actions も可能。

---

## D-001: デモの到達目標を3つとも狙う

**決定** — 次の3つすべてを実演できる状態をゴールとする。

1. **壊して根本原因を突き止めさせる** — アラームを発火させ、Agent にインシデント調査・RCA をさせる
2. **コードのバグを PR で修正させる** — GitHub 連携し、コード起因の不具合を Agent に直させる
   → **[D-017](#d-017-目標2-の到達点を-agent-ready-specification-に縮小する) で到達点を「agent-ready specification の生成」に縮小した。** DevOps Agent は PR を作らないことが確認されたため
3. **CI/CD パイプラインの失敗を調査させる** — GitHub Actions の失敗を Agent にトラブルシュートさせる

**帰結** — 「動くアプリ＋観測可能性＋GitHub 連携＋CI/CD」を一通り揃える必要がある。単なるフォームページでは成立しない。

**却下** — 「トポロジーが見えれば十分」。最小コストだが、調査機能を一切体験できず、目的を満たさない。

---

## D-002: 実行基盤は ECS Fargate + ALB + DynamoDB

**決定** — フォームアプリを ECS Fargate 上のコンテナとして動かし、ALB で受け、DynamoDB に保存する。

**理由** — [インシデント面](../../CONTEXT.md#インシデント面-incident-surface) が最も豊かになる。ALB 5xx・ターゲット異常・タスクの OOM／クラッシュ・CPU 高負荷・デプロイ失敗／ロールバックといった、DevOps Agent が想定する本番障害に最も近い事象を再現できる。

**コスト** — 月額 **約 $55**（東京リージョン単価・[D-013](#d-013-委任された技術判断こちらで決定) の desired = 2 で計算）。

| 内訳 | 月額 |
|---|---|
| ALB（時間課金分） | $17.7 |
| Fargate 0.25vCPU / 0.5GB **× 2タスク** | $22.5 |
| Public IPv4 × 4（タスク ENI ×2 ＋ ALB ノード ×2、$0.005/h） | $14.6 |
| DynamoDB（オンデマンド、デモ規模） | 実質 $0 |

**Public IPv4 課金は NAT を使わない選択から直接発生する。** NAT Gateway（$35/月）を避けた分がここに一部戻ってくるが、それでも NAT 構成より安い。
ALB の LCU、CloudWatch Logs、Container Insights、CloudTrail の保存料は上表に含まない（デモ規模では小さいが、ゼロではない）。

使わない間 `terraform destroy` すれば実質 1日 約 $1.8。

**設計上の制約** — **NAT Gateway を使わない。** 教科書通りにプライベートサブネットへ置くと NAT だけで月 $35 かかり、アプリ本体より高くつく。タスクは public subnet に置く。

**却下**
- **Lambda + API Gateway + DynamoDB** — 月額ほぼ $0 だが、ホスト層が無くトポロジーが薄い。「メモリリークでタスクが OOM」系の面白い RCA が作れない
- **App Runner** — 構築工数は小さいが、マネージドすぎて Agent がいじれるレイヤーが少なく、検証事例も乏しい

---

## D-003: 専用の新規 AWS アカウントを発行する

**決定** — 管理アカウント <管理アカウント ID> から、本プロジェクト専用の[デモアカウント](../../CONTEXT.md#デモアカウント-demo-account)を新規発行する。既存アカウントには相乗りしない。

**理由** — 新規アカウントは既存リソースがゼロなので、**Agent が拾うものすべてが本プロジェクトのもの**になる。タグによるスコープ制御も、IAM ポリシーでの絞り込みも不要になり、設計が単純化される。無料トライアル枠もアカウント単位のため新品で使える。

**経緯** — 当初は「既存アカウント内に新 IAM ユーザーを作って分離する」案だったが、**IAM ユーザーを分けても観測スコープは分離されない**（Agent の可視範囲を決めるのは [Agent Space ロール](../../CONTEXT.md#agent-space-ロール-agent-space-role) のみ）という事実により方針変更。専用アカウント化でこの問題は根本から消滅した。

**注意点**
- アカウント発行にはユニークなメールアドレスが必要 → Gmail のプラスエイリアス（`<管理アカウントのアドレス>+devopsagent@…`）で足りる
- 請求は管理アカウントに集約される → 予算アラームを Phase 0 で入れる
- **SCP の継承を事前検証すること** — 配置先 OU の SCP が ECS / ELB / DynamoDB / `aidevops:*` を弾くと、原因の分かりにくい apply 失敗になる

---

## D-004: 手作業はアカウント発行のみ。以降すべて Terraform

**決定** — **AWS リソースに関する**手作業は「管理アカウントで CreateAccount する」の 1 ステップだけ。それ以降の AWS 側はすべて Terraform が担当する。

**例外（AWS の外側に残る手作業）** — GitHub App の認可と、ペネトレーションテストのターゲットドメイン検証は**ブラウザ操作が必須**で、Terraform では代替できない。
これは [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) に残る（[D-013](#d-013-委任された技術判断こちらで決定) でも同じ点に触れている）。
「手作業はアカウント発行のみ」は **AWS 側について**の話であり、GitHub 側までは含まない。

**例外（AWS 側に残る手作業）— 2026-08-03 に1つ増えた**

| 手作業 | 理由 |
|---|---|
| デモアカウントの `CreateAccount` | 当初からの唯一の手作業 |
| `aws login` でのサインイン | [D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない)。ブラウザ認証が前提の仕組みで、そもそも自動化する対象ではない |
| **Security Agent の Application 有効化** | [D-019](#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる)。アカウントに1つの一度きりの有効化。Terraform で `resource` として書くと既存と重複して apply が落ちる |

いずれも**アカウント単位で一度きり**であり、「以降すべて Terraform」という趣旨自体は保たれている。

**入り方** — ~~Organizations 経由で作ったメンバーアカウントには `OrganizationAccountAccessRole`（AdministratorAccess）が自動生成される。Terraform は管理アカウントの認証情報からこのロールを assume して入る。~~
→ **[D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) で置き換えた。** 管理アカウントの認証情報がそもそもローカルに無く、この前提が成立しなかった。`aws login` でデモアカウントへ直接入る方式に変更している。

**帰結**
- **ルート認証情報を触らない**
- **長期アクセスキーを手で発行・保管しない**
- アカウント ID を変数化しておけば、アカウントごと作り直しても再現できる

**この帰結は [D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) でも保たれる。** `aws login` は短期認証情報とリフレッシュトークンしかローカルに置かず、長期アクセスキーを発行しない。むしろ assume 元として管理アカウントの強い認証情報を手元に置く必要が消えた分、この決定の精神により忠実になった。

**却下**
- **IAM ユーザー＋アクセスキーを手動発行** — Terraform 側は単純になるが、長期認証情報が手元に残る
- **`aws_organizations_account` でアカウント発行も IaC 化** — `terraform destroy` でアカウントを削除できず state から外れて孤児化する。かつ管理アカウントの強権限を常時 Terraform に渡すことになる。サンドボックスにはオーバーキル

---

## D-005: 故障は今は仕込まない。ただし3観点の余地を設計に残す

**決定** — 意図的な故障の実物は今回作らない。何を仕込むかは後で改めて決める。
ただし、アーキテクチャは**次の3観点それぞれを後から発現させられる形**にしておく。

1. **AWS 設定起因** — インフラ設定の変更・誤りに由来する不具合
2. **アプリコード起因** — アプリケーションコードのバグに由来する不具合
3. **セキュリティ起因** — セキュリティに関する問題

**理由** — 故障を先に作り込むと、Agent の実力を測る前に「こちらが用意した答え」に寄ってしまう。
**器だけ作り、弾は後から込める。**

**帰結（これは設計制約になる）** — 「後から仕込める」を保証するために、以下が要件になる。

- Terraform を、健全な設定と劣化した設定を**変数ひとつで切り替えられる粒度**に分解しておく
- アプリを、バグを一箇所に閉じ込めて注入できる構造にし、GitHub と接続しておく
- 3観点それぞれについて「どこを触れば発現するか」を**候補カタログとして書き出す**（実装はしない）

このカタログは [docs/plan/01-fault-perspectives.md](./01-fault-perspectives.md) に置く。

---

## D-006: Security Agent も併せて導入する

**決定** — 観点3（セキュリティ）は「運用障害としてのセキュリティ」に留めず、**脆弱性そのもの**を扱う。そのため **AWS Security Agent も導入対象に含める**。

**理由** — フォームは入力を受け取って処理・表示するため、XSS・インジェクション・入力検証漏れといった脆弱性を仕込む題材として優秀。Security Agent の PR コードレビューと自律ペネトレーションテストを実演できる。

**帰結（スコープ増）**
- 導入サービスが DevOps Agent と Security Agent の**2つ**になる
- Security Agent 用の Agent Space・IAM ロール・GitHub App 連携が別途必要
- ペネトレーションテストは **$50/task-hour** と高額 → 無料トライアル枠内で回す前提にする
- アプリは「脆弱性を仕込める構造」を持つ必要がある（入力をそのまま表示する経路など）

**注意** — **Security Agent の** GitHub App は `OR-Sasaki` に一度しかインストールできず、紐づけ先はデモアカウント1つに固定される（DevOps Agent はこの制約を受けない。[調査済みの外部事実](#aws-security-agent) を参照）。リポジトリ選択では必ず **"Only select repositories"** を選び、既存 27 リポジトリを巻き込まないこと。

---

## D-007: ドメインは決め打ちしない

**決定** — 計画中に特定のドメイン名を前提にしない。ドメインは**デモアカウントの発行に合わせて新しく取り直す**ため、名前が決まるのは後になる。

**設計制約**

- Terraform ではドメインを **任意変数**として扱う（`var.domain_name`、デフォルト `null`）
- **未指定なら ALB の DNS 名でそのまま動く**こと。ドメイン未定が構築のブロッカーになってはならない
- ドメインが決まった時点で、Route53 ホストゾーン＋ACM 証明書＋ALB の HTTPS リスナーを**後付けできる**形にしておく
- 既存アカウント <既存メンバー A> が持つ既存ドメインは**使わない**（別アカウントであり、方針とも合わない）

~~**この決定が成立する根拠** — Security Agent のペネトレーションテストは **HTTP_ROUTE 検証**で ALB の生 DNS 名のまま通る。したがってドメインが無くても観点3のデモは成立する。ドメインは「HTTPS を付けたくなったときの後付け要素」に過ぎない。~~

> **⚠️ この根拠は 2026-08-03 に実測で覆った（[D-042](#d-042-http_route-検証は-https-と有効な証明書を要求するドメインを取得して-dns_txt-に切り替える)）。**
> **HTTP_ROUTE 検証は HTTPS で来て、有効な SSL 証明書を要求する。** `*.elb.amazonaws.com` に対して ACM のパブリック証明書は取れないため、
> **ALB の生 DNS 名では検証が原理的に完了しない。** ドメインは「後付け要素」ではなく、**観点3のペネトレーションテストの前提条件**だった。
>
> **決定そのもの（計画中に特定のドメイン名を前提にしない）は維持する。** 以下の設計制約もすべて生きている
> —— `var.domain_name` は任意変数のままで、未指定なら ALB の DNS 名で動く。
> 覆ったのは「**ドメインが無くても観点3が成立する**」という部分だけである。

---

## D-008: リージョンは ap-northeast-1 に統一

**決定** — アプリも Agent Space（DevOps / Security の両方）も、すべて `ap-northeast-1`。

**理由** — 単一リージョンで完結し構成が単純になる。普段の作業リージョンと一致するため、コンソールを行き来する際の取り違え事故も減る。

**当初の想定は誤りだった（2026-08-02 修正）** — 以前この項には「自動修復 PR が us-east-1 限定かもしれない」というリスクと、「Security Agent の Agent Space だけ us-east-1 に移す」という逃げ道を書いていた。**この逃げ道は成立しない。**
自動修復の配信方式を決めるのは**リージョンではなくリポジトリ可視性**であり、[D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) で Public を選んだ時点で、どのリージョンに置いても修正 PR は出ない（diff 添付になる）。
→ そもそも自動修復は [D-014](#d-014-security-agent-の自動修復はスコープ外) でスコープ外としたため、**このリスクは消滅した。**

**残る唯一のリージョン制限** — DevOps Agent の **Release management（release readiness review / release testing）が us-east-1 のみ（preview）**。

**「3目標すべて東京で成立する」という記述は誤りだった（2026-08-02 の Phase 0 で再訂正）** — 以前この項には次のように書いていた。

> ただし D-001 の3目標（RCA・コードバグの修正・CI/CD 失敗の調査）は、いずれも全リージョン提供の Production operations と On-demand DevOps tasks に属するため、東京で全て成立する。

**目標2 についてこれは成り立たない。** 公式ドキュメントを直接読んだ結果、DevOps Agent が **PR を作成するという記述はそもそも存在せず**、PR に触れる機能（release readiness code review のインラインコメント）は **Release management すなわち us-east-1 限定**だった。詳細と対応は [D-017](#d-017-目標2-の到達点を-agent-ready-specification-に縮小する) に記す。

**目標1（RCA）と目標3（CI/CD 失敗の調査）は Production operations と On-demand DevOps tasks に属するため、東京で成立する。** ここは変わらない。

**この決定は維持する。** [D-017](#d-017-目標2-の到達点を-agent-ready-specification-に縮小する) で目標2 の到達点を Production operations の範囲内に収めたため、us-east-1 に Agent Space を追加する動機は無い。将来 Release management を試したくなったときだけ検討する。

---

## D-009: アプリも Terraform も CI から apply する（完全 GitOps）

**決定** — `main` へのマージで、GitHub Actions が **terraform apply とアプリデプロイの両方**を実行する。

**理由** — 観点1（AWS 設定起因）のデモが**一本の線で繋がる**。

> PR をマージ → Terraform がインフラ設定を変更 → アラームが鳴る → DevOps Agent が調査 → 「直前のデプロイ（= Terraform 変更）が原因」と特定

CI/CD 失敗の調査（デモ目標3）も、アプリ側とインフラ側の**両方**で作れるようになる。

**帰結（ここから3つの設計要件が導かれる）**

1. **GitHub OIDC が必須** — CI に長期アクセスキーを置かず、OIDC で IAM ロールを assume する
2. **Terraform state はリモート必須** — CI とローカルの両方から回るため、S3 バックエンド＋ロックが要る（Terraform 1.13 なので `use_lockfile = true` で DynamoDB テーブル不要）
3. **ブートストラップの順序問題が発生する** — state バケットと OIDC ロールそのものは CI では作れない（CI が動くために必要なものだから）。**ローカルから一度だけ apply する層を分離する**

**引き受けたリスク** — CI が実質 Administrator 相当の権限を持つ。
ただし**専用アカウントなので爆発半径は閉じている**。[D-003](#d-003-専用の新規-aws-アカウントを発行する) の判断がここで効いてくる。

---

## D-010: GitHub リポジトリは Public（`OR-Sasaki/devops-agent-form`）

**決定** — 公開リポジトリにする。`terraform/` / `app/` / `docs/` / `.github/workflows/` を含むモノレポ。

**引き受けたリスク** — 意図的に脆弱なコードと、実際に稼働している脆弱なエンドポイントが**セットで公開**される。第三者が発見して悪用しうる。この判断は明示的に行われたものであり、以下の緩和策を**実装計画の必須要件**として組み込むことで受容する。

**必須の緩和策**

1. **README の冒頭に警告を大書きする** — 「このリポジトリは AWS Security Agent の検証用に意図的な脆弱性を含む。本番で使うな、再利用するな」
2. **本物のシークレットは絶対に置かない。** 観点 3-3 のデモはダミー値で行う
3. **Push Protection への対処** — public リポジトリでは GitHub の Secret Scanning / Push Protection が自動で有効になる。3-3 のデモが **push 時点でブロックされる可能性がある**。実在形式に似せないダミーを使うか、Security Agent 側の指摘のみに絞る
4. **稼働時間を最小化する** — デモしない間は `terraform destroy` する（コスト対策と露出対策を兼ねる）
5. **脆弱性を `main` に常駐させない** — デモの前後で入れて消す

---

## D-011: 撤収はキャンペーン型（検証期間中は起動しっぱなし、期間後に destroy）

**決定** — 「今週は検証期間」と決めてその間は立てっぱなしにし、期間が終わったら `terraform destroy` する。デモのたびに apply/destroy はしない。

**この決定を駆動した非自明な結合** — **ALB を destroy すると DNS 名が変わる。**
Security Agent のペネトレーションテストは検証済みドメインにしか実行されず、その検証（HTTP_ROUTE）は ALB の DNS 名に紐づく。したがって **apply のたびにターゲット登録と検証をやり直す**ことになる。

キャンペーン型なら期間中は DNS 名が固定されるので、**検証は1回で済む**。

**検証期間が具体化した（2026-08-03）** — **1週間以内に全て削除する**方針が決まった。

> **起点の解釈に注意。** 「1週間以内」とだけ合意されており、起点が「この方針を決めた 2026-08-03」なのか
> 「インフラを立ち上げた日」なのかは明示されていない。ここでは**前者（2026-08-03 起点、〜08-10 頃）**と解釈している。
> Phase 1〜4 の構築に数日かかるため、**実際にインフラが稼働している期間はこれより短くなる。**
> コスト見積りは安全側（1週間フル稼働）で置いてある。

**コスト** — **1週間で約 $13**（[D-002](#d-002-実行基盤は-ecs-fargate--alb--dynamodb) の月額 $55 ベース。2週間なら約 $26）。

**無料トライアルの期間は制約にならない** — DevOps Agent / Security Agent とも2ヶ月あり、1週間の検証期間はその内側に完全に収まる。Security Agent の Application を 2026-08-03 に有効化したことで起算が始まっていても影響しない。

> **ただし「期間」と「残枠」は別物である。**
> ペネトレーションテストは **$50/task-hour** で、残枠を使い切っていれば期間内でも課金される。[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) の実行直前の残枠確認は**引き続き必要**（[D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ)）。

**露出** — 脆弱なエンドポイントの公開期間が検証期間に限定される。[D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) の緩和策4を満たす。

---

## D-012: アプリは Hono + TypeScript、題材は問い合わせフォーム＋ `/admin` 一覧

**決定** — Node 22 上の Hono。JSX でサーバーレンダリングし、1コンテナでフォームも API も提供する。
題材は**問い合わせフォーム**（名前・メール・本文）と、送信内容を一覧表示する `/admin`。

**理由** — 依存が極小でイメージが軽く、ECS のデプロイ待ちが短い。デプロイ待ちの短さは、観点1・2のデモを何度も回すときに効いてくる。

**この題材を選んだ理由（3観点すべての仕込み先が自然に取れる）**

| 経路 | 仕込める故障 |
|---|---|
| `POST /submit` の入力処理 | 観点2のバグ（メモリリーク、未処理例外、N+1）と観点3の入力系脆弱性 |
| `GET /admin` の一覧表示 | 観点3-1（XSS）と観点3-4（認証欠如の管理エンドポイント） |
| DynamoDB アクセス | 観点1-1（IAM 権限剥奪）と観点1-5（スロットリング） |

**構造上の要件** — **入力処理を `app/src/submit.ts` の1ファイルに集約する。** [01-fault-perspectives.md](./01-fault-perspectives.md) の「バグを一箇所に閉じ込められる構造」を満たすため。

---

## D-013: 委任された技術判断（こちらで決定）

「言語は任せる」の範囲としてこちらで決めたもの。異論があればいつでも覆せる。

| 項目 | 決定 | 理由 |
|---|---|---|
| Terraform のレイヤー | **`bootstrap/` と `main/` の2層** | [D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops) のブートストラップ順序問題を解くため。`bootstrap/` は state バケットと OIDC ロール自体を作る層なので CI では作れない |
| ECR の置き場所 | **`bootstrap/` 側** | `main/` を destroy してもイメージが残る。[D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy) の destroy のたびにビルドし直すのを避ける |
| state バックエンド | S3 ＋ `use_lockfile = true` | Terraform 1.13 なのでロック用の DynamoDB テーブルは不要 |
| イメージタグ | **コミット SHA** | デプロイとコードを相関させるため（観点2の必須要件）。CI が Terraform 変数として渡し、**Terraform がイメージタグを所有する**ので drift が出ない |
| Agent Space の作成 | **Terraform（`awscc` プロバイダ）** | 再現性のため。ただし GitHub App の認可はブラウザ操作が必須で、そこだけは手作業が残る |
| CloudTrail | **有効化する** | 観点1で「いつ誰が設定を変えたか」を Agent が辿るために必須 |
| ECS タスク数 | desired = 2（AZ 冗長） | 1台だと「1台だけ落ちた」系の事象が作れず、ALB のターゲット異常も再現しにくい |

---

## D-014: Security Agent の自動修復はスコープ外

**決定** — Security Agent の **Automated Remediation（自動修復）を今回のスコープから外す。**
観点3で見るのは **PR コードレビューでの指摘** と **ペネトレーションテストでの実証** の2つまで。修正は人間が行う。

**経緯** — 当初は [D-008](#d-008-リージョンは-ap-northeast-1-に統一) で「自動修復 PR が us-east-1 限定かもしれない」というリージョン問題として扱っていたが、これは**問題の捉え方が間違っていた**。

実際には配信方式を決めるのはリポジトリ可視性で、**public リポジトリでは PR ではなく diff 添付**になる。
つまり [D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) で Public を選んだ時点で、**リージョンをどう動かしても修正 PR は出ない。**

**帰結**

- [D-008](#d-008-リージョンは-ap-northeast-1-に統一) の「引き受けたリスク」と逃げ道は無効化され、リスクごと消滅した
- Phase 0 の確認項目から「自動修復が東京で使えるか」を削除（確認しても意味が無いため）
- [01-fault-perspectives.md](./01-fault-perspectives.md) 観点3-1 の期待動作から「修正 PR」を削除
- **Public を維持できる。** 自動修復のために private 化する動機が無くなった

**却下** — 「自動修復を見るためにリポジトリを Private にする」。[D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) を覆すほどの価値が無く、Public 前提の他の判断（露出管理・警告 README）まで巻き戻る。

---

## D-015: 予算上限は月 $100、通知は管理アカウントのメールへ

**決定** — AWS Budgets を **月 $100** で設定し、**実績 50% / 80% / 100%** と**予測 100%** で管理アカウントのメールアドレスへ通知する。

> **通知先アドレスはリポジトリに書かない。** Public リポジトリなのでクローラに拾われる。
> `terraform/bootstrap/variables.tf` の `budget_notification_email` は default を持たず、実値は gitignore 済みの `terraform.tfvars` に置く（[D-022](#d-022-メールアドレスはリポジトリに置かない)）。

**理由** — [D-002](#d-002-実行基盤は-ecs-fargate--alb--dynamodb) の実費見積りが月約 $55。上限を実費ちょうどに置くと通常運用で鳴り続けて無視する癖がつくため、約2倍を上限に取る。
50% で「想定通り」、80% で「何かが余計に動いている」、100% で「止める判断」という3段階になる。

**注意** — Budgets はあくまで**通知**であって遮断ではない。実際の停止は `terraform destroy`（[D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy)）で行う。

**前提条件** — [D-003](#d-003-専用の新規-aws-アカウントを発行する) で請求を管理アカウントに集約しているため、**デモアカウント側でコストデータが見えるかを Phase 0 で確認する。**
メンバーアカウント自身の予算は作成できるが、Cost Explorer のリンクアカウントアクセスは管理アカウント側の設定に依存する。
ペネトレーションテスト（$50/task-hour）は1回で上限の半分を消費しうるため、**実行前に無料トライアル残枠を必ず確認する。**

---

## D-016: デモアカウントへは `aws login` で直接入る（管理アカウントは経由しない）

**決定** — [デモアカウント](../../CONTEXT.md#デモアカウント-demo-account) **308513050613** へは `aws login --remote` で直接サインインする。**管理アカウント <管理アカウント ID> の認証情報はローカルに一切置かない。**

**経緯** — [D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) は「管理アカウントの認証情報から `OrganizationAccountAccessRole` を assume して入る」と書いていたが、**その管理アカウントへ入る手段が計画に書かれておらず、実際にローカルにも無かった。**
[Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) 着手時に判明した実状は次の通り。

- `default`（<既存メンバー A>）は**アクセスキーが失効済み**で使えない
- `<別アカウントのプロファイル>`（<既存メンバー B>）は有効だがメンバーアカウントであり、`CreateAccount` 等の管理アカウント専用 API には届かない
- したがって「既存アカウントから管理アカウントへ assume する」という逃げ道も塞がっていた

**やり方**

```
aws login --remote --profile devopsagent
```

- **`default` を使ってはいけない。** `~/.aws/credentials` の静的キーは login 認証情報より優先されるため（AWS 公式トラブルシューティングに明記）、失効キーが残っている `default` では認証が通らない。専用プロファイル名を使う
- リージョンは `ap-northeast-1` を事前設定済み（[D-008](#d-008-リージョンは-ap-northeast-1-に統一)）
- セッションは最大12時間。切れたら `aws login` をやり直す
- IAM ユーザーでサインインする場合は managed policy `SignInLocalDevelopmentAccess` が要る。ルートでサインインする場合は追加権限は不要

**Terraform から使うための追加設定（S3 バックエンド対策）**

Terraform AWS プロバイダは 6.23.0 以降で `aws login` に対応済みだが、**S3 バックエンドは未対応**（`terraform` バイナリ組み込みでプロバイダとは別物。ローカルの Terraform 1.13.0 は影響を受ける）。AWS 公式が案内する `credential_process` を橋渡しに使う。

```ini
[profile devopsagent]
login_session = arn:aws:iam::308513050613:root   # aws login が自動で書く
region        = ap-northeast-1
output        = json

[profile devopsagent-tf]
credential_process = /opt/homebrew/bin/aws configure export-credentials --profile devopsagent --format process
region             = ap-northeast-1
output             = json
```

**`credential_process` は絶対パスで書くこと。** `aws` とだけ書くと `sh` が壊れた `/usr/local/bin/aws`（macOS 上の Linux ELF バイナリ）に当たって `exit status 126` になる。詳細は[ローカル環境](#ローカル環境)を参照。

Terraform 側は `devopsagent-tf` を使う。これで **S3 バックエンドを使う `terraform/main/` をローカルから plan できる**（[Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) の完了条件）。

**2026-08-03 に実測で検証済み** — ①`aws login` 直後の `aws configure list` で TYPE が `login` になること ②プロバイダのみなら `devopsagent` で apply が通ること ③S3 バックエンドを足すと `devopsagent` では `No valid credential sources found` で落ちること ④`devopsagent-tf` に切り替えると init・apply が通り state が S3 に書かれること、の4点をすべて確認した。

**帰結**

- **[D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) の帰結は保たれる。** ルート認証情報を保管せず、長期アクセスキーも発行しない。管理アカウントの強権限を手元に置かなくなった分、むしろ D-004 の精神に忠実になった
- **`OrganizationAccountAccessRole` を assume しない。** [Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) の `bootstrap/providers.tf` から `assume_role` ブロックが消え、プロファイル指定だけになる
- **管理アカウントでしかできない確認は Phase 0 の範囲外になる。** 具体的には配置先 OU の SCP 内容の読み取り（`organizations:DescribePolicy` 等）と、Cost Explorer のリンクアカウントアクセス設定。**これらはデモアカウント側から実効性で確認する**（[Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) の項目3・7 を参照）
- 12時間でセッションが切れるため、長時間の作業では再ログインが要る。CI は OIDC なので影響しない（[D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)）

**却下**

- **管理アカウントに IAM ユーザー＋アクセスキーを作る** — 最短だが、組織ルートの管理者相当の長期キーがローカルに残る。爆発半径が組織全体（既存2アカウント含む）に広がり、[D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) に真っ向から反する
- **管理アカウントに、別アカウントのプロファイルから assume できるロールを作る** — 新規の長期キーは増えないが、本プロジェクトと無関係な既存アカウントの長期キーが組織全体への入口になる。[D-003](#d-003-専用の新規-aws-アカウントを発行する)「専用アカウントで爆発半径を閉じる」と逆行する
- **IAM Identity Center を有効化する** — 短期認証情報という点では同等で、権限セットを複数アカウントへ配れる利点もあるが、サンドボックス1つのために組織全体の認証基盤を導入するのは重い。`aws login` で同じ性質（長期キー無し・自動更新）が得られる

---

## D-017: 目標2 の到達点を agent-ready specification に縮小する

**決定** — [D-001](#d-001-デモの到達目標を3つとも狙う) の目標2「コードのバグを PR で修正させる」の期待動作を、**「調査 → 根本原因特定 → agent-ready specification の生成」まで**に縮小する。実際のコード修正は人間または別のコーディングエージェントが行う。

**理由（公式ドキュメントを直接読んで確認した事実）** — **DevOps Agent が PR を新規に開くという記述を、公式ドキュメントのどこにも確認できなかった。**

> **これは「PR 作成機能が存在しない」という証明ではない。** 記述が無いことを機能が無いことの証明として扱わない、という区別をここで明示しておく。
> 確認できたのは「**受け入れ基準に据えられるだけの裏付けが取れない**」ことであり、D-017 はその事実に基づいて期待値を下げる決定である。

**確認できた出力形態**

1. **agent-ready specification** — Production operations の改善提案が生成する構造化文書。問題文・解決方針・対象リポジトリ・変更内容・テスト要件・実装計画を含み、「a structured document that can be handed directly to a coding agent for implementation」と説明される。**PR ではない**
2. **release readiness code review のインラインコメント** — 「Findings appear as inline comments on the affected lines of code」。**既存の PR に対するコメントであって、PR を開く動作ではない**
3. **chat からの fix 生成** — release readiness code review のページに「Request the agent generate a fix for an identified issue」とある。**生成された fix がどう配信されるか（PR か、チャット上の差分提示か）は記載が無い**

**「PR を作らない」と断定できない根拠（外部レビューでの指摘を受けて追記）**

- GitHub App は **Contents を read-write** で要求し、その用途を「Write access enables the agent to **propose fixes** for identified issues」と説明している。**PR 作成に必要な権限自体は持っている**
- 上記3の fix 生成機能がある

**それでもなお PR 作成を受け入れ基準にしない理由**

- [What's new](https://docs.aws.amazon.com/devopsagent/latest/userguide/whats-new.html) の全変更履歴（2026年5〜7月）を確認したが、**PR に関する項目はすべて「PR *に対する*レビュー」**であり、PR を開く機能の追加は無い
- 対照的に、Security Agent 側は「AWS Security Agent **opens a pull request** with the proposed fix」と**明示的に書かれている**。同じ AWS のドキュメント群で、書くべきときには書かれている
- → **確認できない機能を到達目標に据えると、達成/未達の判定ができない。**

**未確認として [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) に残す** — GitHub を Read & Write で接続した後、chat から fix 生成を実際に試し、**何が返るかを観測する**。
PR が返るなら望外の収穫であり、そのとき目標2 を戻せばよい。

さらに 2 には制約が二重にかかる。

- **リージョン** — release readiness code review は Release management に属し、**us-east-1 のみ（preview）**（[D-008](#d-008-リージョンは-ap-northeast-1-に統一)）
- **リポジトリ可視性** — 公式ドキュメントに独立した見出し「Public repository limitation」があり、「Automated PR/MR code review triggers are only available for private repositories」と明記。[D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) の Public 選択と衝突する

つまり目標2 を字義通り実現するには **[D-008](#d-008-リージョンは-ap-northeast-1-に統一)（単一リージョン）と [D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form)（Public）の両方を覆す**必要があり、それでもなお「PR を開く」動作は得られない。

**帰結**

- **構成変更はゼロ。** 東京単一リージョン・Public リポジトリ・現在のコスト見積りをすべて維持できる
- [01-fault-perspectives.md](./01-fault-perspectives.md) 観点2 の「担当は DevOps Agent（RCA → 原因コミット特定 → 修正 PR）」から**「修正 PR」を削除する**
- [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の受け入れ基準は変わらない。項目7（アラーム → ログ → コミットの相関）が目標2 の前提であることに変わりはなく、そこから先が spec 生成になるだけ
- **PR を作る主体は Security Agent だけになる。** ただし [D-014](#d-014-security-agent-の自動修復はスコープ外) で Public のためスコープ外としているので、**本プロジェクトで PR を自動生成するエージェントは存在しない**ことになる

**[D-014](#d-014-security-agent-の自動修復はスコープ外) と同じ扱いである。** 「エージェントの能力を過大に見積もった期待値を、確認できた事実に合わせて下げる」という同一パターンの2件目。

**却下**

- **リポジトリを Private にする（[D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) 撤回）** — Security Agent の修正 PR は復活し（[D-014](#d-014-security-agent-の自動修復はスコープ外) も撤回）、DevOps Agent の PR 自動レビューも発火対象になる。しかし DevOps Agent 側は依然 us-east-1 の Agent Space が別途必要で、Public 前提で組んだ判断（露出管理・警告 README・Push Protection 対処）まで巻き戻る
- **Public のまま us-east-1 に2つ目の Agent Space を追加する** — 公式ドキュメントは「public でも chat や coding agent 連携経由なら release readiness code review を実行できる」としているので手動では回せる。だが [D-008](#d-008-リージョンは-ap-northeast-1-に統一) の単一リージョン方針が崩れ、得られるのは結局「PR へのコメント」であって PR ではない
- **判断を Phase 5 まで保留する** — 実機で覆る性質の制約ではない（公式ドキュメントに明記された仕様であり、設定で変わらない）。保留しても情報は増えない

---

## D-018: Terraform はルートユーザーのまま回す

**決定** — [デモアカウント](../../CONTEXT.md#デモアカウント-demo-account) 308513050613 には `aws login` でルートユーザーとしてサインインし、**そのまま Terraform を回す**。IAM ユーザーは作らない。

**経緯** — [D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) の `aws login` でサインインしたのがルート（`arn:aws:iam::308513050613:root`）だった。新規メンバーアカウントには IAM ユーザーが1つも無いため、**初回にルートで入る以外の選択肢が無かった**。
[D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) の「ルート認証情報を触らない」との折り合いを [Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) の完了時に検討し、このまま進めることにした。

**[D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) の「ルート認証情報を触らない」の解釈を、ここで明示的に確定する。**

> **意味するのは「ルートの長期アクセスキーを作らない・保管しない」であって、「ルートで作業しない」ではない。**

`aws login` はコンソールセッション由来の短期認証情報とリフレッシュトークンしか置かないため、**この解釈のもとで D-004 は破られていない。** [D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) が却下した「IAM ユーザー＋アクセスキーを手動発行」の核心は長期認証情報が手元に残ることであり、そこは回避できている。

**理由**

- **爆発半径が閉じている。** [D-003](#d-003-専用の新規-aws-アカウントを発行する) で専用アカウントにしたため、ルート権限で壊せる範囲は本プロジェクトのリソースだけ。既存2アカウントには一切届かない
- IAM ユーザーを作る手間と、サンドボックスで得られる安全性の差が釣り合わない
- セッションは**最大12時間で自動失効**する。`aws logout` で明示的に破棄もできる

**引き受けたリスク**

- **ルートは IAM ポリシーで制限できない。** 誤操作に対するガードレールが実質 SCP だけになる（[Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) の項目3 で確認したとおり、現状の SCP は何も制限していない）
- AWS の一般的な推奨（ルートは必要な操作に限る）には反する
- アカウントの安全性がコンソールのパスワードと MFA に直結する。→ **2026-08-03 に MFA を有効化済み**（`AccountMFAEnabled = 1` で確認）。この決定の前提条件は満たされている

**却下** — **IAM ユーザーを作り、コンソールパスワードのみ設定して `aws login` し直す**（`AdministratorAccess` ＋ `SignInLocalDevelopmentAccess`）。長期アクセスキーを出さずにルート常用を避けられる正攻法だが、専用サンドボックスに対しては過剰と判断した。方針を変えたくなったらこの案に戻せる（`aws login --profile devopsagent` をやり直すだけで切り替わる）。

---

## D-019: 先行作成した Agent Space は削除し、Terraform に作り直させる

**決定** — 2026-08-03 にコンソールから先行作成した Security Agent の Agent Space **`SandboxAgent`**（`as-d363b56d-…`）を**削除し**、[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) で Terraform に作り直させる。`terraform import` は使わない。

**理由** — [D-013](#d-013-委任された技術判断こちらで決定) の「Agent Space の作成は Terraform（再現性のため）」に最短で戻れる。
削除時点で Target Domain 未登録・ユーザー0・各機能セットアップ前だったため、**失うものが無い。**

**Application は消さない。かつ Terraform でも管理しない** — `SecurityAgent`（`app-966a2407-…`）はアカウントに1つの単位で、実質的なサービス有効化に相当する。Agent Space だけ作り直す。

> **`awscc_securityagent_application` を `resource` として書いてはいけない。**
> state に存在しない既存 Application と重複し、[Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の初回 apply が失敗する。
> **Agent Space は Application を参照しない**（`awscc_securityagent_agent_space` に application 系の属性が無いことをスキーマで確認済み）ので、参照自体が不要。
> ID が必要になったら**読み取り専用の data source**（`awscc_securityagent_application` / `awscc_securityagent_applications`）を使う。

**[D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) の「AWS 側の手作業はアカウント発行のみ」に、例外が1つ増えた** — Security Agent の Application 有効化がコンソール操作として残る。
アカウント単位で一度きりの有効化であり、[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) のブラウザ操作（GitHub App 認可・ペンテストのドメイン検証）と同種のものとして扱う。

**却下** — **`terraform import` で state に取り込む。** 既存を壊さない利点はあるが、名前や属性が Terraform 定義と食い違ったまま state に入り、以後 plan のたびに差分を潰す作業が発生する。空の Agent Space に対して払う代償として大きい。

**注意** — 削除は手作業で行う。**削除が済んでいなくても以降の作業は進めてよい**（[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) で Terraform が作るときに名前が衝突したら、そのとき消せばよい）。

---

## D-020: OIDC ロールの ARN はリポジトリ変数に逃がす

**決定** — GitHub Actions が assume する IAM ロールの ARN を、ワークフローに直書きせず **GitHub のリポジトリ変数**（`vars.AWS_ROLE_ARN`）に置く。ワークフロー側は `${{ vars.AWS_ROLE_ARN }}` と書く。

**理由** — ロール ARN には**アカウント ID が含まれる**。[D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) でリポジトリを Public にするため、直書きするとアカウント ID が恒久的に公開される。
アカウント ID は秘密情報ではなく、これ単体で悪用できるものでもない（[Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) で OIDC の `sub` を `repo:OR-Sasaki/devops-agent-form:*` に絞るため、他リポジトリからは assume できない）。だが**公開しないで済むものを公開する理由も無い。**

**Secrets ではなく Variables を使う** — 秘密ではないため。~~[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) のペンテスト検証用の値（`PENTEST_VERIFICATION_PATH` / `PENTEST_VERIFICATION_TOKEN`）も同じ理由で Variables に置く決まりになっており、**手順が揃う。**~~

> **この2つのリポジトリ変数は [D-038](#d-038-ターゲットドメインは-terraform-で登録し検証発火は-cli-で行う) で消滅した。** 検証トークンは Terraform が computed 属性から直接 ALB へ渡すようになり、人手を経由しない。
> **`AWS_ROLE_ARN` を Variables に置く判断自体は変わらない。** 現在のリポジトリ変数は `AWS_ROLE_ARN` と、
> エージェント連携・ターゲットドメイン登録を有効化する2つの真偽値（`CONNECT_GITHUB_TO_AGENTS` / `REGISTER_PENTEST_TARGET_DOMAIN`）である。

**帰結** — リポジトリ作成直後、`deploy.yml` が動く前に `gh variable set AWS_ROLE_ARN` が必要になる。[Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) の手順に組み込むこと。

---

## D-021: S3 バケット名にアカウント ID を含めない

**決定** — [Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) で作る2つの S3 バケットを、アカウント ID を使わずに命名する。プレフィックスは `or-sasaki`。

| 用途 | バケット名 |
|---|---|
| Terraform state | `or-sasaki-devops-agent-form-tfstate` |
| CloudTrail 証跡 | `or-sasaki-devops-agent-form-cloudtrail` |

**理由** — S3 バケット名をグローバル一意にする定石は「アカウント ID を混ぜる」だが、**state バケット名は `terraform/main/backend.tf` に平文で書かれ、Public リポジトリで公開される。**
`backend` ブロックは変数を受け付けないため、直書きを避けられない。アカウント ID をバケット名に入れると [D-020](#d-020-oidc-ロールの-arn-はリポジトリ変数に逃がす) がロール ARN について回避したのと同じ露出が、別の経路で発生する。

**引き受けたリスク** — 名前の衝突。S3 のバケット名前空間は全 AWS アカウントで共有されるため、他者が同名を先取していれば apply が `BucketAlreadyExists` で落ちる。
`or-sasaki-devops-agent-form-*` は十分に特異なので実害は想定しないが、衝突したら `var.bucket_prefix` を変えて `backend.tf` も合わせて直す。**2026-08-03 の apply では衝突しなかった。**

**却下**
- **`random_id` でサフィックスを生成する** — 衝突は確実に避けられるが、名前が bootstrap の state（ローカル保持）にしか無くなる。`backend.tf` には結局その値を直書きするので**露出は減らず、再現性だけが落ちる**
- **partial backend configuration にしてバケット名を CI から渡す** — `backend.tf` から名前が消えるので露出はゼロになる。だが `terraform init -backend-config=...` が要るようになり、ローカルからの plan（[Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) の完了条件）と CI で手順が分岐する。**バケット名はアカウント ID と違って他アカウントの情報を漏らさない**ので、そこまでの代償を払う価値が無い

---

## D-022: メールアドレスはリポジトリに置かない

**決定** — [D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ) の予算通知先メールアドレスを、リポジトリ内のどのファイルにも平文で置かない。

- `terraform/bootstrap/variables.tf` の `budget_notification_email` は **default を持たない**
- 実値は **gitignore 済みの `terraform/bootstrap/terraform.tfvars`** に置く
- 本ファイルおよび [02-implementation-plan.md](./02-implementation-plan.md) では「管理アカウントのメールアドレス」と記述する

**理由** — [D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) で Public にするため、平文のメールアドレスはクローラに収集されスパムの標的になる。
[D-020](#d-020-oidc-ロールの-arn-はリポジトリ変数に逃がす)（公開しないで済むものを公開しない）と同じ判断を、別の値に適用したもの。

**アカウント ID との扱いの違い** — アカウント ID（308513050613 等）は**伏せない**。
Phase 0 の実測結果は「どのアカウントで何を測ったか」が対応しないと検証可能性を失い、決定ログとしての価値が落ちる。
アカウント ID は単体で悪用できず、OIDC の `sub` を絞っている以上（[Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci)）侵入経路にもならない。
一方メールアドレスは**伏せても文書の検証可能性が一切損なわれない**。**代償の非対称性がこの線引きの根拠である。**

**帰結** — `terraform/bootstrap/` を別環境で再現するには `terraform.tfvars` を手で作る必要がある。
失っても plan が値を尋ねてくるだけで、**リソースは孤児化しない**（bootstrap の state 本体とは性質が違う）。

**この方針は「現在のファイル」だけでは足りない（2026-08-03 の外部レビューで判明）**

Public 化の直前に Codex にレビューさせたところ、**Git 履歴とコミットの author/committer にメールアドレスが残っている**ことが指摘された。実際に確認したところ:

- 全コミットの author / committer が個人の Gmail アドレス
- 過去の blob に、現在のファイルからは消した通知先アドレスが残っている

→ **`git log --all -p` と `git log --format='%ae %ce'` を通さない限り「消した」と言ってはいけない。**
Phase 1 では初回 push の前に履歴を書き換え、次の2つを実施した（[D-025](#d-025-初回-push-の前に-git-履歴を書き換える) を参照）。

**伏せる対象は、メールアドレスだけではない。** 同じレビューで、デモアカウント以外の識別子が
「再現に不要なのに公開されている」と指摘された。次のものを伏せ字に置き換えた。

| 伏せたもの | 理由 |
|---|---|
| AWS Organizations の組織 ID | 本プロジェクトの再現に不要。組織構成を騙る詐称メールの材料になる |
| 管理アカウント ID、既存メンバーアカウント ID | 同上。**本プロジェクトと無関係なアカウント**の情報 |
| 既存アカウントの IAM ユーザー名・ローカルプロファイル名 | 同上 |
| Security Agent の Application ID / Agent Space ID | 先頭のみ残して末尾を省略。同一性の識別には足り、値としては使えない |
| Security Agent のウェブアプリ URL | 実在する到達可能なエンドポイントだった |
| 別アカウントが持つ既存ドメイン名 | 本プロジェクトでは使わないと決めている（[D-007](#d-007-ドメインは決め打ちしない)） |

**デモアカウント 308513050613 だけは伏せない。** 上の「アカウント ID との扱いの違い」で述べたとおり、
Phase 0・Phase 1 の実測結果は**どのアカウントで測ったかが対応しないと検証可能性を失う**ためである。

---

## D-023: OIDC の信頼ポリシーは不変形式の `sub` に切り替える

**決定** — GitHub Actions 用ロールの信頼ポリシーの `sub` 条件を、リポジトリ作成後に**不変形式1件だけ**にする。

```
repo:OR-Sasaki@<owner id>/devops-agent-form@<repo id>:*
```

リポジトリを作る前（`var.github_repo_id` が `null`）は旧形式で置いておく。**両方を並べたままにはしない。**

**理由（公式ドキュメントで確認した事実）** — **2026-07-15 以降に作成された GitHub リポジトリは、`sub` の既定が「不変形式」（immutable subject claims）になる。**
[OIDC reference](https://docs.github.com/en/actions/reference/security/oidc) を 2026-08-03 に直接確認した。原文の構文は
`"repo:OWNER@OWNER-ID/REPO@REPO-ID:ref:refs/heads/BRANCH"`、例は `"repo:octo-org@123456/octo-repo@456789:ref:refs/heads/main"`。
オーナー名とリポジトリ名の**再取得によるなりすまし**を防ぐため、数値 ID が埋め込まれる。

`OR-Sasaki/devops-agent-form` は **2026-08-03 に作成する**ので、この境界の後側に入る。
旧形式だけを書いた信頼ポリシーでは **`sub` が一致せず `AssumeRoleWithWebIdentity` が拒否され、[Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) の完了条件そのものが達成できない。**

> **失敗の向きは安全側である。** 一致しなければ拒否されるだけで、余計な権限は生まれない。
> だが「なぜか assume できない」の原因として非常に特定しづらいので、先に潰す。

**当初は「新旧を並記する」としていたが、外部レビューで覆した（2026-08-03）**

> 最初の案は「どちらが発行されるか確実でないので両方書く。どちらもこのリポジトリだけを指すので許可範囲は広がらない」だった。
> **これは誤りだった。** 2回目の Codex レビューで指摘され、確認したところ次のことが分かる。
>
> **旧形式が抱えている問題そのものが「オーナー名の再取得」である。**
> `OR-Sasaki` が改名またはアカウント削除をした後、第三者がその名前を取得して `devops-agent-form` を作り、
> 自分のリポジトリの OIDC 設定を旧形式に切り替えれば、`repo:OR-Sasaki/devops-agent-form:*` に一致する
> トークンを発行できる。**このロールは AdministratorAccess を持つので、アカウントを丸ごと渡すことになる。**
> 不変形式は**まさにこれを塞ぐために導入された**のに、旧形式を併記すると自分で穴を開け直すことになる。
>
> 「両方書いても許可範囲は広がらない」という当初の理由づけは、
> **`sub` が同一の文字列になりうる条件を考えていなかった**点で成立していない。

**⚠️ ID 部分にワイルドカードを使ってはいけない。** `repo:OR-Sasaki@*/devops-agent-form@*:*` と書くと、
上と同じ理由で不変形式の意味が消える。**数値 ID は実値で固定する。**

**失敗したときの見え方** — 不変形式1件に絞った結果、万一 GitHub が旧形式を発行していれば assume は拒否される。
**これは安全側の失敗**（余計な権限は生まれない）で、Actions のログに即座に出る。
その場合だけ、実際に発行された `sub` を確認してから条件を合わせ直す。**先回りして両方許可することはしない。**

**帰結** — リポジトリ ID はリポジトリを作るまで存在しない。手順が次の順序に固定される。

1. GitHub リポジトリを作成する
2. `gh api repos/<owner>/<repo> --jq .id` と `gh api users/<owner> --jq .id` で ID を取る
3. `terraform/bootstrap/` に `github_repo_id` を渡して再 apply する
4. その後にワークフローを回す

`var.github_repo_id` は default `null` で、**null の間は不変形式を信頼ポリシーに含めない**。初回 apply をリポジトリ作成前に実行できるようにするため。

---

## D-024: サードパーティ action は完全長のコミット SHA で固定する

**決定** — `.github/workflows/` で使う GitHub 以外が配布する action を、**タグではなく完全長のコミット SHA** で参照する。横にバージョンタグをコメントで残す。

```yaml
uses: aws-actions/configure-aws-credentials@e6de054238d6b7531b4efff3b6587d9aade6a06c # v6.2.3
```

**理由** — このワークフローが assume するロールは **`AdministratorAccess` を持つ**（[D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)）。
`@v6` のようなタグ参照は**可変**で、タグの付け替えや配布元リポジトリの侵害があれば、
action が OIDC トークンないし取得後の一時認証情報を外部へ送れる。**デモアカウントを丸ごと奪われる経路になる。**
GitHub 公式も、サードパーティ action を不変のリリースとして使う唯一の方法は完全長 SHA への固定だと述べている。

**引き受けた代償** — 更新が自動で流れてこない。タグから SHA を引き直す手作業が要る。
1週間の検証期間（[D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy)）では更新自体がほぼ発生しないため、代償は小さい。

**却下** — **`actions/*` は GitHub 公式なのでタグのままにする。** 区別を作ると「どれが公式か」を毎回判断することになり、判断の隙間から漏れる。全部 SHA で揃えるほうが単純。

---

## D-025: 初回 push の前に Git 履歴を書き換える

**決定** — GitHub へ最初に push する前に、それまでのローカル履歴を書き換え、
**コミットの author / committer を GitHub の noreply アドレスに置換し、過去 blob からメールアドレスを除去する。**

**理由** — [D-022](#d-022-メールアドレスはリポジトリに置かない) で現在のファイルからメールアドレスを消しても、
**`git log` と過去の blob からは読める。** Public リポジトリでは履歴も全公開されるため、消したことにならない。

2026-08-03 の外部レビュー（Codex）でこれを指摘され、実際に確認したところ**2種類のアドレス**が残っていた。

- 全コミットの author / committer に設定されていた個人の Gmail アドレス
- [D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ) の通知先アドレス（過去 blob）

**やり方** — リモートがまだ存在しない段階なので、`git filter-branch` 相当の書き換えを**代償なしで**実行できる。
push した後では、共有された履歴を壊すことになり同じ手が使えない。**「初回 push の前」であることが条件である。**

`git config user.email` も noreply アドレスに変更する。しないと次のコミットで元に戻る。

**メールアドレス以外も同じ pass で消す。** [D-022](#d-022-メールアドレスはリポジトリに置かない) で現在のファイルから伏せた識別子（組織 ID・他アカウント ID・Agent の ID・既存ドメイン等）も、
過去 blob には残っている。**書き換えるのは1度きりなので、まとめて処理する。**

**帰結** — このリポジトリの `main` は、以前のローカルコミットとは**別のハッシュ**になる。
書き換え前の `.git` は**リポジトリの外**（セッションの作業ディレクトリ）にコピーしてある。
**リポジトリ内の ref として残してはいけない** — `git push --all` や `--mirror` で元のメールアドレスごと公開されうるため。

**検証方法（これを通すまで「消した」と言わない）**

```
git log --all --format='%an %ae %cn %ce'        # コミットメタデータ
git log --all -p | grep -E '<伏せた値の並び>'    # 差分に現れる範囲
git rev-list --objects --all                    # 全 blob を直接 cat-file して走査
```

3つ目まで実施した。**到達可能な全 blob を直接走査してヒット 0** を確認している（`git log -p` は
到達不能な blob やマージの一部を見落としうるため、2つ目だけでは足りない）。

**この決定は一般化できる** — 「Public 化の完了条件」に、現在のツリーだけでなく
**コミットメタデータと全履歴 blob を対象にした走査**を含めること。現在のファイルを見るだけでは不十分である。

---

## D-026: 故障注入は locals で効果値を算出する

**決定** — [D-005](#d-005-故障は今は仕込まないただし3観点の余地を設計に残す) が要求する「変数ひとつで切り替えられる粒度」を、**`terraform/main/fault-injection.tf` の `locals` で効果値を1箇所に算出する**形で実現する。リソース自体は分岐させず、各 `.tf` が `local.fault_*` を読む。

**理由**

1. **何が壊れるかが1ファイルで読める。** 故障ごとに `.tf` をまたいで差分を追う必要がない。これは Agent ではなく**測る側（人間）の要件**で、デモ中に「今どこを壊しているか」を即答できないと Agent の答え合わせができない
2. **`count` による生やし分けを最小にできる。** `count` でリソースごと切り替えると破棄と再作成が起きる。**ALB を作り直すと DNS 名が変わり、ペンテストのターゲット検証が失効する** — [D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy) がキャンペーン型を選んだのと同じ理由がここでも効く
3. **健全な既定値が三項演算子の else 側に必ず現れる。** `"none"` のとき何になるかの確認に他ファイルを開かなくてよい

`count` を使うのは、**リソースの有無そのものが故障である**2件（観点1-3 の SG ingress、観点1-6 のデフォルトルート）だけに限った。

**帰結** — 故障を足すときは `fault-injection.tf` に `local` を1つ足し、対応する `.tf` がそれを読む。**足したら必ず対応するアラームが鳴ることを確認する** — 鳴らない故障は[インシデント面](../../CONTEXT.md#インシデント面-incident-surface)の定義を満たさず、デモとして成立しない。

---

## D-027: ECS のサーキットブレーカーと自動ロールバックを無効にする

**決定** — `aws_ecs_service` の `deployment_circuit_breaker` を `enable = false` / `rollback = false` で**明示的に**書く。

**理由** — 有効にすると、**故障を仕込んだデプロイを ECS が自動で切り戻す。**
[インシデント面](../../CONTEXT.md#インシデント面-incident-surface) の定義は「鳴る・残る・繋がる」であり、**壊れた状態が続いてアラームが鳴り続ける**ことが観点1・2 のデモの前提になっている。自動回復すると、そもそも Agent に調査させる対象が消える。

同じ理由で次の2つも置いていない。

| 置かないもの | 理由 |
|---|---|
| コンテナ単位のヘルスチェック | ECS がタスクを勝手に差し替え、仕込んだ故障が自己回復する。加えて `node:22-slim` に `curl` / `wget` が無い |
| `wait_for_steady_state` | 故障を仕込むと steady state に到達せず、**apply が延々とブロックする**。デプロイ完了待ちは [Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の `deploy.yml` 側で行う（そちらならタイムアウトを制御できる） |

**⚠️ これはサンドボックス固有の判断である。** 本番環境なら3つとも逆の設定にするのが正しい。
**Terraform の既定値と一致していても明示的に書く**のは、既定に流されたのではなく意図した選択だと分かるようにするため。

---

## D-028: 異常ホストアラームは Minimum 統計で見る

**決定** — `UnHealthyHostCount` のアラームを **`Minimum` 統計**で張る。欠損データは計画通り **`breaching`** のままとする。

**理由（ALB の公式ドキュメントで確認した事実）** — [CloudWatch metrics for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html) を 2026-08-03 に直接確認した。原文:

> We recommend you monitor for non-zero `UnHealthyHostCount` in the `Minimum` statistic, and alarm on non-zero value for more than one data point. Using the `Minimum` will detect when targets are considered unhealthy by every node and Availability Zone of your load balancer.

`Minimum` は **LB ノード間**の最小値であって**ターゲット間**の最小値ではない。したがって「2台のうち1台だけ落ちた」場合も、全ノードがそう見ていれば `1` が出て鳴る。[D-013](#d-013-委任された技術判断こちらで決定) が desired = 2 を選んだ狙いは損なわれない。
計画の「>= 1 / 1分 × 2」は、この推奨の「non-zero」「more than one data point」とそのまま一致する。

**`breaching` の根拠が裏付けられた** — 同ドキュメントの Reporting criteria は `UnHealthyHostCount` について **「Reported if there are registered targets」**。
つまり**タスクが全滅して登録ターゲットが1つも無い状態では、メトリクスそのものが消える。** 計画が「異常ホストだけ `breaching`」とした理由（全滅が無音になる）は、推測ではなく文書化された挙動だった。

**引き受けた代償** — 同ページには「Elastic Load Balancing reports metrics to CloudWatch **only when requests are flowing through the load balancer**」ともある。
→ **誰もアクセスしていない時間帯に、このアラームが ALARM に落ちることがある。**
「全滅を見逃す」より「静かなときに鳴る」ほうがましだと判断した。ただし**これは実測ではなく文書からの予測**であり、実際にどう振れるかは [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) で観測して必要なら閾値ごと見直す。

> **⚠️ この代償は実在しなかった（2026-08-03 に実測。[D-039](#d-039-unhealthyhostcount-は-breaching-のまま維持する)）。**
> **`RequestCount` が 0 の25分間も、`UnHealthyHostCount` は毎分 `0.0` を報告し続け、アラームは OK のままだった。**
> 初回 apply の直後に ALARM へ落ちたのは事実だが、原因は「トラフィックが無い」ことではなく
> **「ALB 作成中でまだ登録ターゲットが無い」**ことで、これは上に引用した Reporting criteria
> 「Reported if there are registered targets」の側と一致する。
> 引用した「only when requests are flowing」のほうは、**この指標の実挙動とは一致しなかった。**
>
> → **代償が無いのだから、引き換えに得ていた「全滅を無音にしない」だけが残る。** [D-039](#d-039-unhealthyhostcount-は-breaching-のまま維持する) で維持と決めた。

---

## D-029: エージェントの GitHub 連携は既定で無効にする

**決定** — DevOps Agent・Security Agent とも、GitHub リポジトリの紐づけを **`var.connect_github_to_agents`（既定 `false`）**で囲い、既定では作らない。

**理由** — **GitHub App の認可はブラウザ操作でしか行えず（[D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) の例外）、[Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の初回 apply は必ず認可より前に来る。**
既定で有効にすると、存在しない連携を参照して**初回 apply がその場で落ちる**。これは [D-019](#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる) で `awscc_securityagent_application` を `resource` として書いてはいけないと決めたのと**同じ形の失敗**である — 「Terraform の外で先に成立していなければならないもの」を Terraform に書くと初回 apply が壊れる。

**有効化の手順は既存の経路に揃える** — [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) で認可を済ませた後、リポジトリ変数を足して `deploy.yml` を再実行する。
ペンテスト検証用の値（[D-030](#d-030-ペンテスト検証用の-alb-リスナールールは-phase-2-で書く)）と**まったく同じ入れ方**になるので、手順が1つで済む。**ローカル apply は使わない**（[D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)）。

**未確認のまま残る点** — DevOps Agent 側の association に渡す `service_id` の実値が分からない。
AWS アカウント紐付けはリテラル `"aws"` だと確認済みだが、GitHub 連携が何になるかは**スキーマからは読めない**。コードには暫定で `"github"` と書いてあるが、**これは確認した値ではない。** [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) で実機確認して直す。

> **→ ✅ 実機で確認し、暫定値は誤りだと判明した（2026-08-04）。** 実値は認可時に払い出される **UUID** で、
> `"github"` は `serviceType` のほうの値だった。対応は [D-043](#d-043-github-の-service_id-はリポジトリ変数から渡す) を参照。

---

## D-030: ペンテスト検証用の ALB リスナールールは Phase 2 で書く

**決定** — `var.pentest_verification_path` / `var.pentest_verification_token` と、それを返す `fixed_response` のリスナールールを、**[Phase 3](./02-implementation-plan.md#phase-3-アプリ) ではなく [Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) の `terraform/main/alb.tf` に置く**。

**理由** — 計画はこれを Phase 3（アプリ）の節に書いていたが、**実体はアプリではなく ALB のリスナールールである。**
Phase 3 は `app/` のコードを書くフェーズで、このルールは1行も TypeScript を含まない。`alb.tf` を書いている最中に同じファイルの別ルールとして足すほうが、後から `alb.tf` を開き直すより安全で、リスナーとの優先度の関係もその場で決まる。

**分割損が無いことを確認した** — 両変数の既定は `null` で、**指定されない限りリソースは1つも作られない**（`count = 0`）。
[D-007](#d-007-ドメインは決め打ちしない) の `domain_name` と同じ「未指定でも成立する任意変数」の形なので、Phase 2 に前倒ししても Phase 3・Phase 4 の内容は変わらない。

**Phase 3 に残るもの** — 無い。この項目に関して [Phase 3](./02-implementation-plan.md#phase-3-アプリ) がやることは無くなった。

> **⚠️ 2つの変数は [D-038](#d-038-ターゲットドメインは-terraform-で登録し検証発火は-cli-で行う) で削除した。** リスナールール自体は `alb.tf` に残っており、
> **値の出どころだけが「リポジトリ変数」から「`awscc_securityagent_target_domain` の computed 属性」に変わった。**
> **「実体はアプリではなく ALB のリスナールールである」という D-030 の判断は、そのまま正しかった** ——
> 置き場所が `alb.tf` だったからこそ、値の供給元を差し替えるだけで済んだ。

---

## D-031: DynamoDB のスロットリング監視は ThrottleEvents で行う

**決定** — アラームのメトリクスを、計画の表にある **`ThrottledRequests` から `ReadThrottleEvents` ＋ `WriteThrottleEvents` の合算に差し替える。**

**理由（DynamoDB の公式ドキュメントで確認した事実）** — [DynamoDB Metrics and dimensions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/metrics-dimensions.html) を 2026-08-03 に直接確認した。

- **`ThrottledRequests` のディメンションは `TableName, Operation`** と記載されている
- 同じページは `SystemErrors`（同じく `TableName, Operation`）について明示的に警告している。原文: 「DynamoDB publishes `SystemErrors` only on the `TableName` and `Operation` dimension pair. It does not publish this metric on `TableName` alone. **A CloudWatch alarm that specifies only the `TableName` dimension never matches data and remains in the `INSUFFICIENT_DATA` state**, so specify both `TableName` and `Operation`.」
- 一方 `ReadThrottleEvents` / `WriteThrottleEvents` には **「The `TableName` dimension returns the ... for the table」**と明記されている。**`TableName` 単独で成立することが文書化されている**

> **`ThrottledRequests` が `TableName` 単独で動かないと確認したわけではない。** 上の警告が書かれているのは `SystemErrors` の項であって `ThrottledRequests` の項ではない。
> 確認できたのは「**`TableName` 単独で成立すると文書に書かれているのは ThrottleEvents 側だけ**」ということであり、これは[D-017](#d-017-目標2-の到達点を-agent-ready-specification-に縮小する)と同じ「裏付けが取れるほうを採る」判断である。

**この差し替えを重く見る理由** — 外れたときの失敗が**静か**だからである。
アラームが `INSUFFICIENT_DATA` のまま鳴らず、かつ `treat_missing_data = "notBreaching"` なので、**「設定してあるのに一度も鳴らない」ことに気づけない。** 観点1-5・2-4 のデモが成立しなくなるまで発覚しない種類の誤りなので、文書上の裏付けが厚いほうを採った。

**代替案の却下** — **`ThrottledRequests` に `Operation` を固定する。** ディメンション要件は満たせるが、`PutItem` / `Scan` ごとにアラームが増え、**アラーム定義がアプリの実装に結合する。** アプリが使う API を変えるたびにアラームを直すことになる。

**副次的な利点** — 読み書きのどちらが詰まっているかまで分かる。観点1-5（書き込みスロットリング）と観点2-4（N+1 による読み込み急増）の切り分けがアラームの段階で付く。

---

## D-032: イメージタグは default を持たない必須変数にする

**決定** — `terraform/main` の `var.image_tag` に **default を置かない**。`deploy.yml` の `terraform plan` にも `-var image_tag=${{ github.sha }}` を渡す。

**理由** — default があると、**CI が `-var` を渡し忘れたときに「古い、あるいは存在しないタグ」で apply が静かに成功する。**
イメージタグはデプロイとコードを相関させる要（[観点2](./01-fault-perspectives.md#観点2-アプリコード起因)の必須要件）なので、**間違った値で通るより渡し忘れで止まるほうがよい。** 失敗の向きを安全側に倒す判断で、[D-023](#d-023-oidc-の信頼ポリシーは不変形式の-sub-に切り替える) の「一致しなければ拒否されるだけ」と同じ考え方である。

**`deploy.yml` を Phase 2 で触った理由** — [Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) の `deploy.yml` は `-var` を渡していないため、**この変更を入れると次の push で CI が落ちる。**
Phase 4 を待たずに1行足したのは、[Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) の成果物である「CI が動いている」状態を壊さないため。
渡す値が `github.sha` なのは [Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の apply と同じ値であり、**`plan` は ECR にイメージが実在するかを確認しない**ので、push 前でも通る。

**ローカルから plan するときは `-var image_tag=bootstrap` を付ける。** [Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) が言う「plan を通すためだけのダミー値」がこれにあたる。

> **⚠️ ただし初回 apply 以降、このダミー値で drift を判定してはいけない（2026-08-03 に実測）。**
> デプロイ済みのイメージタグと食い違うため、**`plan` は必ずタスク定義の置換とサービス更新を計画する。**
>
> ```
> Plan: 1 to add, 1 to change, 1 to destroy.
> ```
>
> これは drift ではなく**ダミー値の副作用**である。`plan` が空であることを確認したいときは、
> **実際にデプロイされているコミット SHA を渡す** —— `-var image_tag=$(git rev-parse HEAD)`。
> [D-037](#d-037-awscc-の永続的な差分は-config-側を-api-に合わせて潰す) が守ろうとしている「`plan` の出力が信用できる状態」は、**読み方まで含めて初めて成立する。**

---

## D-033: bootstrap の state はスナップショットを S3 に置く

**決定** — `terraform/bootstrap/terraform.tfstate` を **`s3://or-sasaki-devops-agent-form-tfstate/bootstrap-backup/terraform.tfstate` に一度だけコピーする。** バックエンドの移行はしない。

**背景** — bootstrap の state は[ローカルにしか無く](#d-013-委任された技術判断こちらで決定)、`.gitignore` で除外されている。失うと 14 リソースが**孤児化**する（作り直しは可能だが名前が衝突する）。要否は未決のままだった。

**なぜ移行ではなくスナップショットなのか**

| 案 | 判断 |
|---|---|
| **何もしない** | 却下。孤児化したら 14 リソースをコンソールから手で消すことになる |
| **スナップショットを1回置く（採用）** | bootstrap は [Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) で完成しており、**以後変更する予定が無い。** 継続同期の価値が低い |
| **S3 バックエンドへ移行する** | 却下。バックエンドを変えると bootstrap 側も `devopsagent-tf` プロファイルが要るようになり（[D-016](#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない)）、**完成して動いている層を検証期間の直前に触ることになる。** state バケット自身の state をそのバケットに置く循環も生じる |

**この対策が守る範囲を正しく述べる** — 守れるのは**ローカルの喪失**（ディスク障害・誤削除・作業ディレクトリの取り違え）だけである。
**バケットごと失う事故は守れない**（同じバケットに置いているため）。ただしバケットにはバージョニングとパブリックアクセスブロックが有効で、[撤収手順](./02-implementation-plan.md#コストと撤収)が言う通り `terraform destroy` では消えない。

**⚠️ この state にはメールアドレスが含まれる。** `budget_notification_email`（[D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ)）が値として入っている。
[D-022](#d-022-メールアドレスはリポジトリに置かない) が禁じているのは**リポジトリに置くこと**であって、同一アカウント内の非公開 S3 バケットに置くことではない。パブリックアクセスブロックが4項目とも `true` であることを確認したうえで実施した。**このバケットを公開設定にしてはいけない。**

**bootstrap を変更したら取り直すこと。** 自動同期はしていないので、スナップショットは古くなりうる。

---

## D-034: 観点 1-2 と 1-6 の想定症状を訂正する

**決定** — [01-fault-perspectives.md](./01-fault-perspectives.md) の観点1-2 と 1-6 に書かれていた**発現する症状を訂正する。** 仕込み方と期待回答は変えない。

**経緯** — [Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) のコード（`c7b95a9`）に対する **7回目の外部レビュー（Codex）** で指摘され、公式ドキュメントで裏を取った。

**1-2「ターゲット全台 unhealthy → 503」は誤り**

ALB は**全ターゲットが unhealthy になると fail-open する。**
[Health checks for Application Load Balancer target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html) を 2026-08-03 に直接確認した。原文:

> If a target group contains only unhealthy registered targets, the load balancer routes requests to all those targets, regardless of their health status. This means that if all targets fail health checks at the same time in all enabled Availability Zones, **the load balancer fails open**. The effect of the fail-open is to allow traffic to all targets in all enabled Availability Zones, regardless of their health status, based on the load balancing algorithm.

→ アプリ自体は生きているので、**利用者のリクエストは成功し続ける。** 鳴るのは `UnHealthyHostCount` アラームだけ。

> **観点そのものは壊れていない。** 期待回答は「ヘルスチェック設定の変更。**アプリ自体は生きている**」であり、
> fail-open はその期待回答と**むしろ整合する**。誤っていたのは症状欄の記述だけである。

**1-6「ECR から pull できずタスク起動失敗」は、そのままでは起きない**

デフォルトルートを消しても**稼働中のタスクは走り続ける。** 失うのは DynamoDB と CloudWatch Logs への外向き通信である。
ECR の pull が落ちるのは**次にタスクを起動しようとしたとき**なので、再現には `aws ecs update-service --force-new-deployment` 等でタスクの置き換えを起こす必要がある。

**⚠️ その一手を Terraform に持ち込んではいけない。**
故障の値をタスク定義の環境変数に載せれば置き換えは起きる（レビューが提案した対処がこれだった）が、
**それでは Agent がタスク定義を読むだけで答えが分かってしまう。** [D-001](#d-001-デモの到達目標を3つとも狙う) の目標1（根本原因を突き止めさせる）が成立しなくなるので、採らない。
タスク置き換えは**故障を仕込む人間の手順**として Terraform の外に置く。

**⚠️ 副作用** — ALB も同じ public subnet に居る。インターネット向け ALB はデフォルトルートに依存するため、
**この故障はサイト全体が到達不能になる方向に振れうる。** 1-6 を実際に使うときは織り込むこと。

**レビューの3件目は採らなかった** — 「サービスの `MemoryUtilization` は分母がタスク定義の 512 MiB なので観点1-4 では発火できない」という指摘（severity: high）。
**指摘の根拠として挙げられたページが、指摘と逆のことを書いている。**
[Amazon ECS service utilization metrics](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service_utilization.html) の原文:

> If you specify a soft limit (`memoryReservation`), it's used to calculate the amount of reserved memory. Otherwise, **the hard limit (`memory`) is used**.

本構成は `memoryReservation` を指定せずコンテナ側の `memory`（故障時 64 MiB）だけを置いているので、**分母が 64 になる可能性がある。**
そうであれば OOM 直前に 100% 近くまで上がり、アラームは鳴る。

> **どちらが正しいかは文書からは決まらない。**「鳴らない」と断定した指摘は退けるが、「鳴る」とも言えない。
> **未確認事項として残し、[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) で実測する。**
> 観点1-4 の根拠は元々 EventBridge のタスク停止イベント（`stoppedReason` に OOM が入る）なので、どちらに転んでも設計は成立する。

**帰結** — 訂正は症状の記述と Terraform のコメントに閉じており、**リソース定義は1つも変わらない。** `terraform plan` の結果（45 リソース）も変わらない。

---

## D-035: ベースラインには観点3 の故障を1つも置かない

**決定** — [Phase 3](./02-implementation-plan.md#phase-3-アプリ) で書くアプリのベースラインは、**[01-fault-perspectives.md](./01-fault-perspectives.md) の[観点3](./01-fault-perspectives.md#観点3-セキュリティ起因) に挙がっている項目を1つも含まない状態**にする。
具体的には **`/admin` に Basic 認証を付け、セキュリティヘッダを出す。**

**この判断が要った理由** — 計画のルート表は `GET /admin` を「送信一覧」とだけ書いており、**認証の有無を決めていなかった。**
一方 [観点3-4](./01-fault-perspectives.md#観点3-セキュリティ起因) は「認証・認可のない管理エンドポイント」を**故障として**挙げている。
認証なしの `/admin` を最初から置くと、**それ自体が観点3-4 を先に仕込んだことになる。**

これは [D-005](#d-005-故障は今は仕込まないただし3観点の余地を設計に残す)（故障は今は仕込まない）に反し、かつ [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) 項目10 の前提を壊す。
項目10 は「この時点のコードに脆弱性は無い」ことを前提に、**Security Agent が `No issues identified.` とコメントすれば合格**としている。
脆弱性が実在すれば指摘が返るのが正しい動作であり、**そのとき「接続できている」と「問題が無い」の区別がつかなくなる。**

**観点3 の各項目をベースラインでどう扱うか**

| # | 故障 | ベースラインの実装 | 仕込むときに触る場所 |
|---|---|---|---|
| 3-1 | XSS | `hono/jsx` が `{}` の値を自動エスケープする。`raw()` を使わない | `app/src/admin.tsx` |
| 3-2 | インジェクション | `Scan` に `FilterExpression` を使わない。式を文字列連結で作らない | `app/src/submit.ts` / `db.ts` |
| 3-3 | ハードコードされたシークレット | 置かない。管理者パスワードは Terraform 生成 → SSM SecureString → ECS `secrets` | — |
| 3-4 | 認証なしの管理エンドポイント | **`/admin` に Basic 認証**。認証情報が無いときは 503 で閉じる | `app/src/admin.tsx` の `adminAuth` |
| 3-5 | 過剰な CORS | CORS ミドルウェアを**入れない**（同一オリジンのみ） | `app/src/index.tsx` |
| 3-6 | レート制限なし | **入れない（下記）** | — |
| 3-7 | セキュリティヘッダ欠如 | `hono/secure-headers` ＋ `default-src 'none'` の CSP | `app/src/index.tsx` |

**⚠️ 3-6（レート制限）だけは例外として、ベースラインに入れない。**

**他の観点のデモを阻害するため。** 観点1-5（DynamoDB のスロットリング）・[観点2-3](./01-fault-perspectives.md#観点2-アプリコード起因)（レイテンシ悪化）・観点2-4（N+1）は、いずれも **`POST /submit` に負荷をかけて発現させる**設計になっている。
レート制限を入れると、故障を仕込んだ後に**その故障を発現させられなくなる。**

> **これは「ベースラインに観点3 の故障を1つも置かない」という原則を1件破っている。**
> 破っていることを承知のうえで、代償を比べて選んだ。
> **[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) 項目10 で Security Agent がレート制限の欠如を指摘した場合、それは「指摘として妥当」であり、接続失敗ではない。**
> 判定は「`No issues identified.` が返るか」ではなく「**コメントが付くか**」で行い、内容がレート制限のみなら合格とする。
> 項目10 の本来の価値は「コメントが付かない = 接続できていない」を切り分けることにあり、そこは損なわれない。

**管理者パスワードの持ち方**

パスワードをどこに置くかで、**別の故障（3-3）を仕込んでしまう**危険がある。次の経路にした。

```
random_password（Terraform が生成）
  → aws_ssm_parameter（SecureString・既定の AWS マネージドキー）
  → ECS の container_definitions.secrets で ADMIN_PASSWORD として注入
```

- **リポジトリには平文が1文字も残らない。** ハードコードすれば 3-3 そのものになる
- **タスク定義にも平文が残らない。** `environment` に置くと `describe-task-definition` とコンソールから読めてしまう。`secrets` なら参照（ARN）しか残らない
- **`terraform plan` の出力にも出ない。** `random_password.result` と `aws_ssm_parameter.value` はどちらも sensitive として `(sensitive value)` に伏せられる（実測で確認）。[Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の `pr.yml` は plan を**公開リポジトリの PR にコメントする**ので、これは必須の性質だった
- ユーザー名（`var.admin_username`、既定 `admin`）は秘密ではないので平文でよい

**実行ロールに要る権限は `ssm:GetParameters` だけである。**
ECS の公式ドキュメント [Amazon ECS task execution IAM role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html) の「Secrets Manager or Systems Manager permissions」を 2026-08-03 に直接確認した。原文:

> `kms:Decrypt` — **Required only if your secret uses a customer managed key and not the default key.** The ARN for your custom key should be added as a resource.

`key_id` を指定していない = 既定の AWS マネージドキー（`alias/aws/ssm`）なので、KMS の許可は要らない。

**引き受けたリスク** — **タスクが起動しない原因が1つ増える。**
実行ロールが `ssm:GetParameters` を持たないと、タスクは `ResourceInitializationError` で起動に失敗する。
[Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) が警戒している3つの原因（`assign_public_ip` の指定漏れ・イメージのアーキテクチャ違い・`image_tag` の不一致）に4つ目が加わる。

> **ただし症状は混ざらない。** `stoppedReason` の文字列が `CannotPullContainerError` とは別物（`unable to pull secrets or registry auth`）なので、区別はつく。
> あわせて `aws_ecs_service` の `depends_on` に IAM ポリシーを明示し、**権限が揃う前にタスクが起動を試みる**順序そのものを潰した。

**却下**

- **認証なしの `/admin` を置き、観点3-4 は「最初から仕込まれている」ものとして扱う** — 実装は最も軽い。だが [D-005](#d-005-故障は今は仕込まないただし3観点の余地を設計に残す)（器だけ作り、弾は後から込める）を1件だけ破ることになり、**破った1件が [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) 項目10 の判定基準と正面から衝突する**
- **パスワードを `environment` に平文で渡す** — SSM も IAM ポリシーも要らず、タスク起動の失敗要因が増えない。だが値がタスク定義に残り、**「シークレットを環境変数に平文で置いている」こと自体が指摘対象になりうる。** 3-3 を避けたつもりで別の形の 3-3 を作る
- **ALB のリスナールールで `/admin` を塞ぐ** — アプリを触らずに済むが、観点3-4 の仕込み先が Terraform 側へ移る。[D-012](#d-012-アプリは-hono--typescript題材は問い合わせフォーム-admin-一覧) は `/admin` の一覧表示を**アプリ側の**仕込み先と決めており、そこがずれる

---

## D-036: fork からの PR では AWS を使うジョブを実行しない

**決定** — `pr.yml` の `terraform plan` ジョブに `if: github.event.pull_request.head.repo.full_name == github.repository` を付け、**同一リポジトリのブランチから出た PR でだけ実行する。**
app の lint / typecheck / test / build と、terraform の fmt / validate は**誰の PR でも走らせる。**

**理由** — **リポジトリは Public なので、誰でも fork から PR を出せる**（[D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form)）。
`pull_request` イベントの fork 由来の実行には **OIDC トークンもシークレットも渡らない**（GitHub の仕様）。したがって AWS を使うステップは**必ず失敗する。**

**失敗すること自体は安全側である。** 権限が漏れるのではなく、単に assume できないだけ。
問題は判定のほうで、**「CI が赤い」が常態化すると [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の受け入れ確認が濁る。** 特に項目10（Security Agent が PR にコメントするか）は PR を1本出して見る項目なので、既に赤い CI と混ざると読み取りにくい。

**ジョブを3つに割る形にした。** 1つのジョブの中でステップ単位に `if` を散らすより、
「AWS が要るか要らないか」の境界がジョブ境界と一致していたほうが、後から見て分かる。

| ジョブ | AWS 認証情報 | fork からの PR |
|---|---|---|
| `app` | 不要 | **走る** |
| `terraform-check`（fmt / validate） | 不要（`init -backend=false`） | **走る** |
| `terraform-plan` | 必要（OIDC） | **走らない**（skip） |

`terraform validate` に認証情報が要らないのは、`init -backend=false` で S3 バックエンドへ接続せず
プロバイダのスキーマだけを取得できるため。**fork からの PR でも Terraform の構文エラーは捕まる。**

**⚠️ `pull_request_target` は使わない。**
fork のコードをベースリポジトリの権限で走らせるイベントで、これを使えば fork からでも plan は通る。
だが **このワークフローが触れるのは `AdministratorAccess` を持つロールである**（[D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)）。
第三者が書いた `terraform/` や `app/` を、その権限が届く文脈で評価させる構成は、[D-024](#d-024-サードパーティ-action-は完全長のコミット-sha-で固定する) が action の固定にまで気を使っている水準と釣り合わない。
**得られるのは「fork の PR でも plan が見える」という利便性だけで、代償が大きすぎる。**

**引き受けた代償** — fork からの PR では、**Terraform の変更が実際に何を作り変えるかを CI が見せない。**
`main` へ入れる前に plan を見たければ、レビュー側でブランチをこのリポジトリに引き取って PR を出し直す。
検証期間が約1週間（[D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy)）で、外部からの PR を想定していないため、この代償は実質ゼロである。

**あわせて決めたこと（同じワークフロー内の細部）**

- **PR の `terraform plan` は `-lock=false` で回す。** plan は state を書かない読み取り専用の操作である一方、`main` への push で走る `deploy.yml` の apply は**10分以上ロックを保持しうる**。ロックを取りに行くと、PR の plan が apply の裏で待たされて無意味に落ちる
- **plan 結果のコメントは `gh pr comment` で行う。** `actions/github-script` 等を足すと [D-024](#d-024-サードパーティ-action-は完全長のコミット-sha-で固定する) で SHA 固定すべき依存が増える。`gh` は `ubuntu-latest` にプリインストールされている
- **plan の出力は 55000 バイトで切り詰める。** GitHub のコメント上限は 65536 文字で、48 リソースの plan は容易に超える。全文は Actions のログに残す

---

## D-037: awscc の永続的な差分は config 側を API に合わせて潰す

**決定** — 初回 apply の後に `terraform plan` を回して見つかった**永続的な差分**を、**API が実際に保存している形に config を寄せる**ことで解消する。`ignore_changes` では隠さない。

**経緯** — 初回 apply の直後、コードを1行も変えていない状態で `plan` が **`0 to add, 2 to change, 0 to destroy`** を返した。
[D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops) は「Terraform にイメージタグを所有させると drift が出ない」と書いているが、**drift が出ていたのはイメージタグではなく `awscc` の2リソースだった。**

**原因は3箇所あり、2種類に分かれる。**

| 箇所 | config | API が返す値 |
|---|---|---|
| `awscc_devopsagent_association.configuration.aws.resources` | `[]` | `null` |
| `awscc_securityagent_agent_space.integrated_resources` | `[]`（`connect_github_to_agents = false` のとき） | `null` |
| `awscc_securityagent_agent_space.aws_resources.log_groups` | ロググループの **ARN** | ロググループの **名前** |

1. **空リストと未設定は別物である。** `awscc` は「空リストを渡す」を「未設定」として保存し、refresh では `null` を返す。
   config に `[]` を書いている限り、**Terraform は毎回「`null` → `[]`」の更新を計画し続ける。**
   → `null` を書けば往復する。
2. **`log_groups` は ARN を渡しても名前に正規化されて保存される。**
   → `aws_cloudwatch_log_group.app.name` を渡せば往復する。
   **⚠️ 同じ `aws_resources` の中でも `iam_roles` と `vpcs` は ARN のまま往復する。** リソース単位でも属性単位でもなく、**属性ごとに扱いが違う。**

**修正後、apply を1回も挟まずに `plan` が `No changes.` になった。** 実インフラは元々 API の形で保存されており、ずれていたのは config の側だったことが確認できる。

**なぜ `lifecycle { ignore_changes }` を使わないのか**

- **差分が消えるのではなく、見えなくなるだけである。** `ignore_changes` を張った属性は、**本当に変えたくなったときも Terraform が追随しない。**
- **[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の判定と正面から衝突する。** 観点1 のデモは「Terraform の変更がインシデントを起こしたことを Agent が突き止める」ことを見るもので、**`plan` の出力が信用できる状態であることが前提**になっている。毎回2件の嘘の変更が出ていると、本物の1件がそこに埋もれる。
- **`pr.yml` が plan を PR にコメントする**（[D-036](#d-036-fork-からの-pr-では-aws-を使うジョブを実行しない)）。常に差分が出ていると、レビューで「いつもの2件」を読み飛ばす癖がつく。**それは観点1 のデモが壊れることと同義である。**

**一般化** — **`plan` が通ったことは、`apply` 後に `plan` が空になることを意味しない。**
[Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) の完了条件は「`plan` が通ること」だったので、この種の誤りは**構造的に初回 apply の後でしか見つからない。**
`awscc` は Cloud Control API 越しにスキーマだけを見ており、**「書いた値がどう保存されるか」はスキーマに現れない。**
→ **awscc のリソースを足したときは、apply の後にもう一度 `plan` を回して空になることを確かめる。**

---

## D-038: ターゲットドメインは Terraform で登録し、検証発火は CLI で行う

**決定** — ペネトレーションテストのターゲットドメインを `awscc_securityagent_target_domain` で**登録**し、
computed で返る検証用の値を **ALB のリスナールールへ直接**渡す。**検証の発火だけは CLI で行う。**

```
terraform apply (CI)                     ← 登録。トークンが computed で返る
  awscc_securityagent_target_domain
        │ verification_details.http_route.{route_path, token}
        ▼
  aws_lb_listener_rule.pentest_verification

aws securityagent verify-target-domain --target-domain-id <id>   ← 発火。ここだけ CLI
```

**なぜ Terraform だけで完結しないのか（CLI で確認した事実）** — **`verify-target-domain` は独立した API である。**
`awscc` は Cloud Control API 越しの **CRUDL しか行わず**、アクション系 API を呼ぶ口を持たない。
`verification_status` が computed なので「読める」が、**「待てる」わけではない。**

**この決定で消えたもの** — `var.pentest_verification_path` / `var.pentest_verification_token` と、
リポジトリ変数 `PENTEST_VERIFICATION_PATH` / `PENTEST_VERIFICATION_TOKEN`、およびブラウザ操作。
**トークンが人手を1度も経由しなくなった。**

**残した安全弁** — `var.register_pentest_target_domain`（既定 `false`）で囲った。
[D-029](#d-029-エージェントの-github-連携は既定で無効にする) と同じ理由で、**未検証の `awscc` リソースを初めて動かすときは、失敗を1つの変更に切り分けられる状態で有効化する。**

**⚠️ apply が通っても、実際に URL を取得するまで正しさは分からない。** 実際に2件の誤りが apply 後に見つかった。

| 誤り | 症状 |
|---|---|
| API が返す `routePath` に**先頭の `/` が無い** | ALB の path-pattern が**永久に一致せず**、リクエストはアプリへ流れて 404。plan も apply も通る |
| トークンを**生のまま** `text/plain` で返していた | 公式指定は `{"tokens": ["<token>"]}` の JSON |

→ **[D-037](#d-037-awscc-の永続的な差分は-config-側を-api-に合わせて潰す) の教訓がそのまま2度目に効いた。** `awscc` を足したら apply 後に `plan` を回すだけでなく、
**そのリソースが実際に外から期待通りに見えるかまで確かめる。**

**却下** — **ブラウザで登録し、提示された値をリポジトリ変数に入れて再 apply する**（当初の計画）。
成立はするが、**公開配信されるだけの値を人が2回コピーする**手順が残る。
[D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy) のキャンペーン型なら1回で済むとはいえ、ALB を作り直すたびに再取得が要る。

---

## D-039: UnHealthyHostCount は breaching のまま維持する

**決定** — `treat_missing_data = "breaching"` を維持する。**[D-028](#d-028-異常ホストアラームは-minimum-統計で見る) を覆さない。**

**理由 — 覆す動機だった「静かな時間帯の偽陽性」が、実測で否定された。**
[Phase 5・6 の実機確認結果](#phase-56-の実機確認結果2026-08-03) の通り、**`RequestCount` が 0 の25分間もアラームは OK のままだった。**
メトリクスが欠けていたのは「登録ターゲットがまだ無い」ALB 作成中の数分間だけで、これは公式の Reporting criteria
**「Reported if there are registered targets」**と一致する。

> **つまり [D-028](#d-028-異常ホストアラームは-minimum-統計で見る) が「代償」として引き受けたものは、本構成では発生していない。**
> 代償が無いのだから、**それと引き換えに得ていた「タスク全滅を無音にしない」だけが残る。** 覆す理由が無い。

**引き受けたリスク** — 観測窓は約1時間で、「二度と鳴らない」ことの証明ではない。
**ALB を作り直すたびに、作成中の数分間は同じ ALARM が出る**（実際に初回 apply で出た）。
デモ中に ALB を作り直す変更は入れない方針（[D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy)・[D-026](#d-026-故障注入は-locals-で効果値を算出する)）なので、実害は初回だけである。

**却下**

- **`notBreaching` に戻す** — 偽陽性が実在しないので、得るものが無い。**タスク全滅時にメトリクスごと消えて最も重い障害が無音になる**という [D-028](#d-028-異常ホストアラームは-minimum-統計で見る) の懸念だけが残る
- **デモ中は常時トラフィックを流す** — 運用手順が増えるだけで、**アラーム状態はトラフィックに依存しないことが分かった**以上、得るものが無い

---

## D-040: ペネトレーションテストは実行しない

**決定** — [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の項目9 は**ターゲットドメインの検証完了までで閉じる。** ペネトレーションテスト自体は実行しない。

**理由** — 項目9 の受け入れ条件は「**ターゲット検証が完了している**」であって「実行した」ではない。
一方コストは **$50 / task-hour** で、[D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ) の上限 $100 の半分を1回で消費しうる。
**無料トライアルの残枠は CLI から読めない**（[Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) 項目6 で確認済み。`securityagent` に使用量系 API が無く、`freetier get-free-tier-usage` は空を返す）ため、
**残枠が読めないまま実行してはいけない**という [D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ) の制約が最後まで解けない。

**帰結**

- `awscc_securityagent_pentest` は**書かない。** Terraform に置くと `apply` が課金を発火させることになり、「デプロイ = `terraform apply`」（[D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)）と正面から衝突する
- **コンソールでの残枠確認も不要になった。** 実行しないので確認する意味が無い
- **検証済みドメインは残るので、後から実行する判断に戻せる。** 失うものは無い

---

## D-041: 撤収時に Security Agent の GitHub App をアンインストールする

**決定** — 撤収手順（[02-implementation-plan.md](./02-implementation-plan.md#コストと撤収) の項目3）として、**Security Agent の GitHub App を `OR-Sasaki` からアンインストールする。**

**理由** — 「A GitHub App can only be installed once to a GitHub account or GitHub organization.」（[Connect to GitHub](https://docs.aws.amazon.com/securityagent/latest/userguide/connect-github.html)）。
**デモアカウントは撤収時に閉じる可能性がある**（[02-implementation-plan.md](./02-implementation-plan.md#コストと撤収) の項目4）ため、放置すると
**`OR-Sasaki` が「消えたアカウントに紐づいたまま」になり、将来別の AWS アカウントで Security Agent を使えなくなる。**

代償は撤収時の作業が1つ増えるだけで、**非対称性が大きい。**

**⚠️ DevOps Agent 側は外さなくてよい。** [What's new](https://docs.aws.amazon.com/devopsagent/latest/userguide/whats-new.html) の 2026-06-30 の項の通り、複数の AWS アカウントから同じ GitHub アカウントに接続できるため、同じ問題が起きない。**2つのエージェントで扱いが違う。**

---

## D-042: HTTP_ROUTE 検証は HTTPS と有効な証明書を要求する。ドメインを取得して DNS_TXT に切り替える

**決定** — カスタムドメインを取得し、ターゲットドメインの検証方式を **HTTP_ROUTE から DNS_TXT へ切り替える。**

**経緯 — [D-007](#d-007-ドメインは決め打ちしない) の成立根拠が実測で覆った。** [D-007](#d-007-ドメインは決め打ちしない) はこう書いていた。

> **この決定が成立する根拠** — Security Agent のペネトレーションテストは **HTTP_ROUTE 検証**で ALB の生 DNS 名のまま通る。したがってドメインが無くても観点3のデモは成立する。

**これは誤りである。** 公式ドキュメントと実測の両方が、HTTPS と有効な証明書を要求している（原文は[調査済みの外部事実](#aws-security-agent)に引用した）。

そして **`*.elb.amazonaws.com` に対して ACM のパブリック証明書は取得できない。** そのドメインを所有しているのは AWS であり、
DNS 検証もメール検証も通せない。→ **ALB の生 DNS 名では、HTTP_ROUTE 検証は原理的に完了しない。**

**なぜ DNS_TXT を選ぶか** — **証明書の問題を丸ごと回避できる。**
DNS_TXT はドメインの所有を TXT レコードで示すだけで、**HTTPS も証明書も要求しない。**
加えてドメインを Route 53（同一アカウント）に置けば、公式の **One-click verification** が使える。原文:

> **If the domain is registered in Route 53 (same AWS account):** AWS Security Agent can create the DNS record automatically.

**⚠️ ドメイン代は検証期間より長く残る。** [D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy) の検証期間は約1週間だが、**ドメイン登録は最低1年である。**
`terraform destroy` では消えず、デモアカウントを閉じる場合は移管するか失効させることになる。
**インフラのコスト見積り（[D-002](#d-002-実行基盤は-ecs-fargate--alb--dynamodb)）の外側にある費用**として、ここに明記しておく。

**却下**

- **自己署名証明書を ACM にインポートして 443 を開ける** — 公式が「**valid** SSL certificate」と書いており、公開インターネット上の検証元が信頼しない証明書を通す見込みが薄い。**確かめていないので「通らない」と断定はしない**が、ドメインを取れば確実に解決する問題に対して、不確実な回避策を試す順序ではない
- **サポートケースで手動検証を依頼する** — 公式に経路がある（原文は[調査済みの外部事実](#aws-security-agent)に引用）。だが応答待ちが検証期間（〜2026-08-10）に収まる保証が無い
- **項目9 を未達のまま閉じる** — 登録・トークン配信・検証発火の経路はすべて動いており、**残るのは証明書だけ**である。ここで止めると[観点3](./01-fault-perspectives.md#観点3-セキュリティ起因)の「実際にデプロイされたものに到達できるか」が確かめられないまま終わる

---

## D-043: GitHub の service_id はリポジトリ変数から渡す

**決定** — `awscc_devopsagent_association.github` の `service_id` を **`var.devops_agent_github_service_id`（既定 `null`）**に逃がし、実値は GitHub Actions のリポジトリ変数 `DEVOPS_AGENT_GITHUB_SERVICE_ID` から渡す。

**経緯 — [D-029](#d-029-エージェントの-github-連携は既定で無効にする) が「確認した値ではない」と警告していた箇所が、実際に誤っていた。**
GitHub App の認可を済ませてから `list-services` を叩いたところ、実値は**リテラルではなく UUID** だった。

```json
{
  "serviceId": "612f7046-…",
  "serviceType": "github",
  "additionalServiceDetails": { "github": { "owner": "OR-Sasaki", "ownerType": "user" } }
}
```

> **`serviceType` が `"github"` で、`serviceId` は別物である。** コードは `service_id = "github"` と書いていたので、
> **型としては通るが実体を指さない。** `service_id` は API から見ればただの文字列なので
> **`plan` では捕まらず `apply` で落ちる** —— [D-029](#d-029-エージェントの-github-連携は既定で無効にする) が予告していた失敗の形そのものだった。

**なぜリポジトリ変数なのか（コードに直書きしない理由）**

| | 判断 |
|---|---|
| **`var.github_repo_id` は直書きしている** | GitHub の公開 API から誰でも読める値だから（[D-023](#d-023-oidc-の信頼ポリシーは不変形式の-sub-に切り替える) で ID を取得した経緯どおり） |
| **`service_id` は直書きしない** | **AWS の認証情報が無いと読めないアカウント固有の識別子**である。[D-020](#d-020-oidc-ロールの-arn-はリポジトリ変数に逃がす)（公開しないで済むものを公開する理由も無い）をそのまま適用した |

加えて**この値は永続的でない。** アカウントを作り直したり GitHub App を入れ直したりすると変わるので、
**コードではなく環境側の設定として持つほうが正しい。**

**渡し忘れを2箇所で止める** — 値が無いまま連携を有効にすると、`null` が API に届いて分かりにくいエラーになる。

1. `awscc_devopsagent_association.github` の `lifecycle.precondition` — **`plan` の時点で止まる**
2. `deploy.yml` — Terraform を起動する前に落とす。CI のログで理由が先に読める

[D-032](#d-032-イメージタグは-default-を持たない必須変数にする) と同じ「**間違った値で静かに通るより、渡し忘れで止まるほうがよい**」という判断である。

**一般化** — **`plan` が通ることは、値が正しいことを何も意味しない。**
`service_id` のような不透明な識別子は、プロバイダから見ればただの文字列である。
[D-037](#d-037-awscc-の永続的な差分は-config-側を-api-に合わせて潰す)（`plan` が通っても `apply` 後に差分が残りうる）と [D-038](#d-038-ターゲットドメインは-terraform-で登録し検証発火は-cli-で行う)（`apply` が通っても URL を取得すると 404 だった）に続く3件目で、
**いずれも「Terraform が通ったこと」を正しさの根拠にしてはいけないという同じ教訓に帰着する。**

---

## D-044: DevOps Agent の GitHub association は Terraform で管理しない

**決定** — `awscc_devopsagent_association.github` を**削除する。** DevOps Agent 側の GitHub 連携は、
コンソールでの認可が作ったものをそのまま使う。**`import` もしない。**
Security Agent 側は Terraform で管理を続けるが、`integration` にはリテラルではなく **integration ID** を渡す。

**経緯 — [D-043](#d-043-github-の-service_id-はリポジトリ変数から渡す) を直して apply したら、別の2件で落ちた。** どちらも [D-029](#d-029-エージェントの-github-連携は既定で無効にする) が想定していなかった形である。

**1件目 — 認可が association まで作っていた**

```
Resource of type 'AWS::DevOpsAgent::Association' with identifier
'f0797e94-…' already exists.. ErrorCode: AlreadyExists
```

認可の直後に `list-associations` を叩くと、**Terraform が作ろうとしていたものと同じ association が既に存在していた。**

| | 値 |
|---|---|
| `associationId` | `ea5c1bf7-…`（作成 2026-08-04T05:02:50Z = 認可した時刻） |
| `serviceId` | `612f7046-…` |
| `configuration.github` | `repoName` / `repoId` / `owner` / `ownerType` すべて期待どおり |

> **[D-019](#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる) とまったく同じ形である。** 「Terraform の外で先に成立しているもの」を `resource` で書くと apply が壊れる。
> [D-029](#d-029-エージェントの-github-連携は既定で無効にする) はこの原理を自分で書いていたが、**認可が association まで作るとは想定していなかった。**
> 想定していたのは「認可しないと参照先が無い」ことであって、「認可すると参照先ごと出来上がる」ことではなかった。

**2件目 — `integration` は属性名と裏腹に ID を要求する**

```
Value 'GITHUB' at 'integrationId' failed to satisfy constraint:
Member must satisfy regular expression pattern: i-[a-zA-Z0-9\-]+
```

`awscc_securityagent_agent_space` の属性名は `integration` だが、**API は `integrationId` として検証する。**
実値は認可時に払い出される `i-` 始まりの ID（`aws securityagent list-integrations` で取れる）。

**なぜ import しないのか** — [D-019](#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる) と同じ理由。
ブラウザ操作が作ったものを state に取り込むと、**属性が Terraform 定義と食い違ったまま入り、以後 plan のたびに差分を潰す作業が発生する。**
association は空の器に近く、払う代償に見合わない。

**帰結**

- **`var.connect_github_to_agents` が効くのは Security Agent 側だけになった。** 名前と実体がずれるが、
  Security Agent 側は依然この変数で制御されており、変数を分けるほどの利得が無い。**ずれていることを変数の description に明記した**
- **`var.devops_agent_github_service_id` は削除した。** どのリソースにも渡らない変数を置かない。
  実値の取り方は [D-043](#d-043-github-の-service_id-はリポジトリ変数から渡す) に、管理しない理由はここに書いてある
- **接続の確認はコンソールを開かずに済む** — `aws devops-agent list-associations --agent-space-id <id>`

**一般化（3件目なので、もう傾向と呼んでよい）**

| 決定 | 「通った」のに正しくなかったもの |
|---|---|
| [D-037](#d-037-awscc-の永続的な差分は-config-側を-api-に合わせて潰す) | `plan` が通っても、apply 後に `plan` が空になるとは限らない |
| [D-038](#d-038-ターゲットドメインは-terraform-で登録し検証発火は-cli-で行う) | `apply` が通っても、URL を取得すると 404 だった |
| [D-043](#d-043-github-の-service_id-はリポジトリ変数から渡す) / **D-044** | `plan` が通っても、**識別子が実体を指しているとは限らない** |

**`awscc` はスキーマしか見ておらず、値の意味を検証しない。**
`service_id` / `integration` のような不透明な識別子は、プロバイダから見ればただの文字列である。
→ **エージェント系のリソースを足したときは、`apply` の成功ではなく「API がその実体を返すか」で確認する。**

---

## D-045: コードレビューを見るときだけ一時的に private にする

**決定** — [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の項目10（PR に Security Agent のコードレビューコメントが付く）を確認するときだけ、
リポジトリを**一時的に private にし、確認が済んだら public に戻す。** [D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form)（Public）は最終状態として維持する。

**経緯** — [調査済みの外部事実](#aws-security-agent) は Security Agent の PR コードレビューについて「リポジトリ可視性による制限は無い」と書いていたが、**誤りだった。**
`leave_comments = true` で apply したところ API が 400 で拒否した。

```
Public GitHub repositories are supported for pentesting and not for code review comments.
```

**これは検索結果の要約ではなく、AWS のサービス自身が拒否した一次観測である。**
`list-integrated-resources` も接続先を `"accessType": "PUBLIC"` として記録しており、可視性を見ていることが分かる。

**なぜ「未達で閉じる」でも「恒久的に private」でもないのか**

| 案 | 判断 |
|---|---|
| **項目10 を未達として閉じる** | 却下。**接続できていないのか、可視性で無効なだけなのかを切り分ける**という項目10 本来の価値が得られない。ここを確認しないと、観点3 のデモで「コメントが付かない」を見たときに原因を特定できない |
| **恒久的に private にする** | 却下。[D-010](#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) を覆すと [D-014](#d-014-security-agent-の自動修復はスコープ外)（自動修復をスコープ外にした前提）と [D-017](#d-017-目標2-の到達点を-agent-ready-specification-に縮小する) の根拠も同時に変わる。**1項目の確認のために3つの決定を巻き戻す**のは釣り合わない |
| **確認のときだけ private（採用）** | 項目10 を実測できて、最終状態は Public のまま。代償は運用手順が1つ増えること |

**手順（順序が唯一の防御である）**

```
1. gh repo edit OR-Sasaki/devops-agent-form --visibility private
2. gh variable set ENABLE_PR_CODE_REVIEW_COMMENTS --body true  → deploy
3. PR を出す（⚠️ draft では発火しない。必ず Ready for review）
4. コメントを確認したら false に戻して deploy
5. gh repo edit … --visibility public
```

> **⚠️ 4 を 5 より先に行うこと。** public に戻してから false にしようとすると、
> **その apply 自体が「public なのに true」で落ちる。** 順序を逆にすると自分で自分を詰ませる。

**⚠️ Terraform はリポジトリの可視性を知らない。** そのため `variables.tf` 側では検証できない。
`deploy.yml` に `gh repo view --json visibility` で実際の可視性を見るガードを置き、
**public のまま true にしたら Terraform を起動する前に止める**ようにした。
[D-043](#d-043-github-の-service_id-はリポジトリ変数から渡す) / [D-044](#d-044-devops-agent-の-github-association-は-terraform-で管理しない) と同じく「間違った値で apply に到達させない」という方針である。

**private の間に起こることを織り込む** — [D-014](#d-014-security-agent-の自動修復はスコープ外) の前提（public なので修正 PR は出ない）が**その間だけ成立しない。**
`remediate_code` は `false` 固定なので自動修復は動かないが、**「public だから出ない」ではなく「明示的に切ってあるから出ない」に根拠が変わる。**

**public に戻した後、コメント機能は再び使えなくなる。** デモのたびにこの手順を回すことになる。

---

## D-046: pr.yml の plan には deploy.yml と同じ変数を渡す

**決定** — `pr.yml` の `terraform plan` に、`deploy.yml` の `apply` と**同じ変数を同じ条件で**渡す。

**経緯** — [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) 項目10 の確認用に出した [PR #2](https://github.com/OR-Sasaki/devops-agent-form/pull/2) で、**テストを足しただけの差分に対して plan がこう出た。**

```
Plan: 1 to add, 1 to change, 3 to destroy.
  # aws_route53_record.pentest_verification[0] will be destroyed
  # awscc_securityagent_target_domain.pentest[0] will be destroyed
```

**検証済みのターゲットドメインを破棄する計画**である。原因は `pr.yml` が
`register_pentest_target_domain` 等を渡しておらず、`variables.tf` の既定（`false`）が効いていたこと。

> **これは嘘の差分であって、本物の変更ではない。**
> 放置すると「いつもの destroy」を読み飛ばす癖がつき、**本物の1件がそこに埋もれる。**
> [D-037](#d-037-awscc-の永続的な差分は-config-側を-api-に合わせて潰す) が `ignore_changes` を却下したのとまったく同じ理由である。

**⚠️ この差分は「見えるだけ」では済まない。** `terraform/main/` の apply 経路は CI 1本（[D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)）なので
PR の plan がそのまま apply されることは無いが、**もし誰かがこの plan を信じて手で apply すれば
検証済みドメインが消え、[D-042](#d-042-http_route-検証は-https-と有効な証明書を要求するドメインを取得して-dns_txt-に切り替える) の検証をやり直すことになる。**

**一般化** — **plan と apply で変数の渡し方が違えば、plan は apply の予告ではなくなる。**
機能フラグをリポジトリ変数で足すたびに、**2つのワークフローの両方に足す**こと。

---

## D-047: 連携 ID は Variables ではなく Secrets に置く

**決定** — `SECURITY_AGENT_GITHUB_INTEGRATION_ID` を GitHub の **Variables から Secrets へ移す。**
あわせて Terraform の `var.security_agent_github_integration_id` に **`sensitive = true`** を付ける。

**経緯 — [D-046](#d-046-pryml-の-plan-には-deployyml-と同じ変数を渡す) の修正そのものを Security Agent が指摘した。** [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) 項目10 の確認で出した PR に対し、
**この値が公開経路に載ると指摘された。** 指摘を鵜呑みにせず実測して確かめた結果は次の通り。

| 指摘された経路 | 実測 |
|---|---|
| plan 出力 → PR コメント | **出ていなかった。** 当該リソースに差分が無ければ値は plan に現れない |
| **Actions のログ** | **出ていた。** ステップの `env:` ブロックが展開されてそのまま記録される |

```
terraform plan  SECURITY_AGENT_GITHUB_INTEGRATION_ID: <実値>
```

> **`::add-mask::` では防げない。** env ブロックの展開は `run:` のスクリプトが動く前に記録されるため、
> スクリプト内でマスクを宣言しても間に合わない。**Secrets にすれば GitHub が自動でマスクする。**

**[D-020](#d-020-oidc-ロールの-arn-はリポジトリ変数に逃がす) の「Secrets ではなく Variables」と矛盾しないのか** — 矛盾しない。[D-020](#d-020-oidc-ロールの-arn-はリポジトリ変数に逃がす) が Variables を選んだ理由は
**「秘密ではないから」**である。一方この値については、[D-044](#d-044-devops-agent-の-github-association-は-terraform-で管理しない) 自身が「リポジトリには置かない」と決めていた。
**置かないと決めた値がログに出るなら、置き場所の選択が間違っている。**

> **⚠️ この値は資格情報ではない。** AWS の認証情報が無ければ使えない不透明な識別子で、
> [D-022](#d-022-メールアドレスはリポジトリに置かない) が Agent Space ID について言う「同一性の識別には足り、値としては使えない」ものと同じ性質である。
> **深刻な漏洩ではない。** それでも直すのは、[D-020](#d-020-oidc-ロールの-arn-はリポジトリ変数に逃がす) の「公開しないで済むものを公開する理由も無い」に照らして一貫していないからである。

**⚠️ 既存の Actions ログには実値が残っている。** public に戻す前に、当該 run を削除すること。
**「現在のファイルから消した」は「消した」ではない**（[D-025](#d-025-初回-push-の前に-git-履歴を書き換える)）という原則が、ここではログに適用される。

**2件目の指摘（`pr.yml` のネスト構造）も直した** — `enable_pr_code_review_comments` の分岐を
`connect_github_to_agents` の外側に書いていたため、`deploy.yml` と構造が非対称だった。

> **ただし指摘された「plan と apply がずれる」実害は、現時点では発生しない。**
> この変数は `security-agent.tf` で `connect_github_to_agents ? [...] : null` の**内側にしか現れない**ため、
> `connect` が false なら参照されず、値を渡しても plan は変わらない。
> **指摘はコードの形について正しく、影響について過大だった。** それでも直したのは、
> 参照が1箇所増えた瞬間に本物のずれになるためである。

---

## 未決事項

**判断事項は無い。** D-001〜D-047 で解消済み。新しい判断が生じたら D-048 以降として追記する。

### 未確認のまま残っている事実

判断ではなく、実機で確かめる項目。

- ~~**Security Agent の無料トライアル残枠**（[Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) 項目6）~~ → **✅ 確認が不要になった（2026-08-03）。**
  CLI から読めないことは変わらない（`securityagent` に使用量系 API が無く、`freetier get-free-tier-usage` は空を返す）が、
  **[D-040](#d-040-ペネトレーションテストは実行しない) でペンテストを実行しないと決めたため、残枠を知る必要が消えた。**
  実行する判断に戻すときは、コンソールで残枠を見るところからやり直すこと（[D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ) の制約は生きている）
- ~~**`devops-agent get-account-usage` が `AccessDenied` になる理由**~~ → **✅ 解決（2026-08-03）。仮説①「オンボード前は使えない」が正しかった。**
  [Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の初回 apply で DevOps Agent の Agent Space が実体化した直後に再試行したところ、**`ap-northeast-1` では正常に応答するようになった**（`monthlyAccountInvestigationHours` 等の4項目、いずれも `limit: -1` / `usage: 0.0`）。
  **一方 `us-east-1` は `AccessDeniedException` のままである。** そちらには Agent Space を作っていない。
  → **この API は「そのリージョンに Agent Space が存在すること」を要求する。** 権限や請求データの所在（仮説②）でもルート固有の制限（仮説③）でもなかった。
  なお `limit: -1` は無料トライアルの残枠を示す値ではないため、**[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) の Security Agent の残枠確認は依然としてコンソールで行う必要がある**（そもそも別サービスの API である）
- ~~**コストデータに実際の課金が乗ってくるか**~~ → **✅ 乗った（2026-08-04）。ただし完全な判定は 2026-08-05 まで待つ。**

  **2026-08-03 の実績は $1.0254。** これは**稼働 12.3 時間ぶんの部分日**である（11:42 UTC 開始）。
  24 時間に引き伸ばすと **約 $2.0/日**。

  | 内訳（8/3 の実績） | 金額 | 24h 換算 | [D-002](#d-002-実行基盤は-ecs-fargate--alb--dynamodb) の見積り |
  |---|---|---|---|
  | ECS（Fargate ×2） | $0.321 | $0.63 | $0.75 |
  | ELB | $0.267 | $0.52 | $0.59 |
  | VPC（Public IPv4 ×4） | $0.209 | $0.41 | $0.49 |
  | **CloudWatch** | **$0.202** | **$0.39** | **見積りに含めていない** |
  | その他（S3 / ECR / DynamoDB 等） | $0.026 | — | — |

  > **見積りの3項目はいずれも下振れしている**（合計 $1.56 対 見積り $1.81）。
  > **超過分はまるごと CloudWatch である。** [D-002](#d-002-実行基盤は-ecs-fargate--alb--dynamodb) は「ALB の LCU、CloudWatch Logs、Container Insights、
  > CloudTrail の保存料は上表に含まない（**デモ規模では小さいが、ゼロではない**）」と書いていたが、
  > **「小さい」は誤りで、実際には請求の約 20% を占める。** Container Insights が `enhanced` であることが効いている。
  >
  > **予算上限（月 $100、[D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ)）に対する脅威にはならない。** 1週間で約 $14 であり、[D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy) の見積り（約 $13）とほぼ一致する。

  **⚠️ 2026-08-04 の日次は照会時点で `0` を返す。** これは反映遅延であって「コストが見えない」ではない
  （[Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) で同じ誤読をしかけた経緯がある）。**部分日からの外挿ではない確定値は 2026-08-05 に読める。**
  **HOURLY 粒度は使えない** — 支払いアカウント側の Cost Explorer 設定でのオプトインが要る（`AccessDeniedException`）。
- ~~**DevOps Agent の GitHub 連携を Terraform でどこまで書けるか**~~ → **✅ 解決（2026-08-04）。境界がはっきりした。**

  | 段階 | どこでやるか |
  |---|---|
  | GitHub App の**認可** | **ブラウザ必須。** `register-service` の許容値に GitHub が無く、help に「**excludes OAuth 3LO services**」と明記されている |
  | Agent Space への**紐づけ** | **Terraform で書ける。** `awscc_devopsagent_association` の `configuration.git_hub` に `owner` / `owner_type` / `repo_name` / `repo_id` を渡す |

  **`service_id` の実値は認可時に払い出される UUID だった**（`"github"` は `serviceType` のほう）。
  リポジトリ変数から渡す形にした経緯は [D-043](#d-043-github-の-service_id-はリポジトリ変数から渡す) を参照。
- ~~**`UnHealthyHostCount` のアラームが、トラフィックの無い時間帯に ALARM へ落ちるか**~~ → **✅ 落ちない（2026-08-03 に実測。一度目の結論を訂正した）。**
  初回 apply の直後に ALARM になったのは事実だが、**原因はトラフィックの不在ではなく「ALB 作成中でまだ登録ターゲットが無かった」ことだった。**
  `RequestCount` が 0 の25分間もアラームは OK のままで、メトリクスは毎分 `0.0` を報告し続けている（[Phase 5・6 の実機確認結果](#phase-56-の実機確認結果2026-08-03)）。
  → **[D-028](#d-028-異常ホストアラームは-minimum-統計で見る) が代償として書いていた偽陽性は、本構成では発生しない。** 扱いは [D-039](#d-039-unhealthyhostcount-は-breaching-のまま維持する) で「維持」と決めた
- **サービスの `MemoryUtilization` の分母が、タスク単位の 512 MiB とコンテナ単位の hard limit のどちらか** — [D-034](#d-034-観点-1-2-と-1-6-の想定症状を訂正する) の通り**公式ドキュメントからは決まらない。** 観点1-4 でメモリアラームが鳴るかがこれで変わる（設計自体はどちらでも成立する）。
  → **⚠️ 「Phase 6 で実測する」は成立しない。健全な状態では測っても分からない。**
  `fault_injection = "none"` のとき `local.container_memory_hard_limit` は `var.task_memory` と同じ **512** になる（`fault-injection.tf`）。
  **2つの候補が同じ値なので、どちらが分母でもメトリクスは一致する。** 実際 2026-08-03 の実測値は 1.3〜4.9% で、どちらの解釈でも矛盾しない。
  → **切り分けられるのは観点1-4 を実際に仕込んだとき（コンテナ側だけ 64 MiB に落としたとき）だけである。**
  分母が 64 なら使用率は約8倍に跳ね、512 のままなら値は変わらない。**この一度の観測で決着する**

- **`/admin` の認証（[D-035](#d-035-ベースラインには観点3-の故障を1つも置かない)）を Security Agent がどう評価するか** — ベースラインから観点3 の故障を外したが、**レート制限（観点3-6）だけは意図的に入れていない。**
  [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の項目10 でこれが指摘されるかは分からない。指摘されても接続失敗ではないので合格とする、という扱いは D-035 に書いた
- **観点1-5 で確実にスロットリングを起こす負荷条件** — 低容量プロビジョンド（1 WCU）に落とした後、どれだけの送信で `WriteThrottleEvents` が立つかは決めていない。故障を実際に仕込むときに詰める（[D-005](#d-005-故障は今は仕込まないただし3観点の余地を設計に残す) の範囲外）
- ~~**`awscc_securityagent_target_domain` で HTTP_ROUTE 検証まで完了できるか**~~ → **✅ 完了できない（2026-08-03 に実測）。理由は2つあり、性質が違う。**
  1. **検証の発火が別 API である。** `verify-target-domain` は独立したアクション系 API で、`awscc`（Cloud Control の CRUDL のみ）からは呼べない。
     ただし**登録とトークン配信は Terraform で完結する**ので、ブラウザ操作とリポジトリ変数は消えた（[D-038](#d-038-ターゲットドメインは-terraform-で登録し検証発火は-cli-で行う)）
  2. **そもそも ALB の生 DNS 名では HTTP_ROUTE 検証が成立しない。** 検証は HTTPS で来て有効な証明書を要求し、`*.elb.amazonaws.com` に ACM のパブリック証明書は取れない（[D-042](#d-042-http_route-検証は-https-と有効な証明書を要求するドメインを取得して-dns_txt-に切り替える)）
