# 決定ログ

グリルセッションで確定した決定を、決まった順に記録する。用語は [CONTEXT.md](../../CONTEXT.md) に従う。

**ステータス: 決定確定（D-001〜D-034）／未決事項なし／Phase 0・Phase 1・Phase 2 完了／検証期間は 2026-08-10 頃まで**
2026-08-02 のグリルセッションで全項目を解消。同日の外部レビューを受けて D-014・D-015 を追加し、[D-002](#d-002-実行基盤は-ecs-fargate--alb--dynamodb) のコスト見積りと [D-008](#d-008-リージョンは-ap-northeast-1-に統一) のリスク認識を訂正した。
同日の [Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) の実機確認で D-016・D-017 を追加し、[D-008](#d-008-リージョンは-ap-northeast-1-に統一) の「3目標すべて東京で成立する」という記述を**再度訂正した**（[D-017](#d-017-目標2-の到達点を-agent-ready-specification-に縮小する) を参照）。
[Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) 完了時に D-018・D-019 を、Phase 1 の着手準備で D-020 を追加した。
[Phase 1](./02-implementation-plan.md#phase-1-ブートストラップ--最小-ci) の実施中に、公開リポジトリへの露出に関する判断として D-021・D-022 を追加し、初回 push 直前の外部レビュー（Codex）の指摘を受けて D-023〜D-025 を追加した。
[Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) で `terraform/main/` を書く過程で D-026〜D-033 を追加し、**アラーム表のメトリクスを1件訂正した**（[D-031](#d-031-dynamodb-のスロットリング監視は-throttleevents-で行う)）。初回コミット後の外部レビュー（7回目）を受けて D-034 を追加した。以降に新しい判断が生じたら D-035 以降として追記する。

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
| PR コードレビューの挙動 | 「Ready for review」で発火（draft は対象外）。解析開始時にコメントを出し、完了後に指摘をまとめて1レビューで投稿。**指摘ゼロでも `No issues identified.` とコメントする** → 脆弱性を仕込まなくても接続確認に使える。リポジトリ可視性による制限は無い |

**GitHub 連携（公式ドキュメントで確認済み）**

- **個人ユーザーアカウントで連携可能。** 登録時の Account type に `Organization` と **`User`** の選択肢がある → `OR-Sasaki` のままで良く、GitHub organization を新設する必要はない
- **GitHub App は1つの GitHub アカウントに一度しかインストールできない（Security Agent の話。DevOps Agent は違う）。** [Connect to GitHub](https://docs.aws.amazon.com/securityagent/latest/userguide/connect-github.html) に「A GitHub App can only be installed once to a GitHub account or GitHub organization. If you need to connect the same GitHub organization to AWS Security Agent, you must use the same AWS account where the integration was first registered.」とある。つまり `OR-Sasaki` は**ただ1つの AWS アカウント**にしか紐づけられない。デモアカウントに紐づけると、後から別アカウントで使いたくなったらアンインストールが必要
  → **DevOps Agent には同じ制約は無い。** [What's new](https://docs.aws.amazon.com/devopsagent/latest/userguide/whats-new.html) の 2026-06-30 の項に「You can now connect AWS DevOps Agent in multiple AWS accounts and Regions to the same GitHub organization or account. If the AWS DevOps Agent GitHub App is already installed, additional accounts and Regions reuse the existing installation」とある。**2つのエージェントで制約が違うので、まとめて扱わないこと**
- リポジトリ選択は **All / Only select repositories** から選べる → **必ず "Only select repositories"** を選ぶこと。All を選ぶと既存の 27 リポジトリすべてが Security Agent のスコープに入る

**ペネトレーションテストのターゲットドメイン検証**

- 検証方式は **DNS_TXT** と **HTTP_ROUTE** の2つ。**AWS はテストを検証済みドメインに対してのみ実行する**
- **ALB が対象の場合は HTTP_ROUTE が推奨。** エージェントがパスとトークンを提示し、HTTP で取得して検証する。ALB は元々到達可能なのでそのまま通る
- → **カスタムドメインは必須ではない。** ALB の生 DNS 名で成立する

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

**この決定が成立する根拠** — Security Agent のペネトレーションテストは **HTTP_ROUTE 検証**で ALB の生 DNS 名のまま通る。したがってドメインが無くても観点3のデモは成立する。ドメインは「HTTPS を付けたくなったときの後付け要素」に過ぎない。

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

**Secrets ではなく Variables を使う** — 秘密ではないため。[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) のペンテスト検証用の値（`PENTEST_VERIFICATION_PATH` / `PENTEST_VERIFICATION_TOKEN`）も同じ理由で Variables に置く決まりになっており、**手順が揃う。**

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

---

## D-029: エージェントの GitHub 連携は既定で無効にする

**決定** — DevOps Agent・Security Agent とも、GitHub リポジトリの紐づけを **`var.connect_github_to_agents`（既定 `false`）**で囲い、既定では作らない。

**理由** — **GitHub App の認可はブラウザ操作でしか行えず（[D-004](#d-004-手作業はアカウント発行のみ以降すべて-terraform) の例外）、[Phase 4](./02-implementation-plan.md#phase-4-cicd-の拡充) の初回 apply は必ず認可より前に来る。**
既定で有効にすると、存在しない連携を参照して**初回 apply がその場で落ちる**。これは [D-019](#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる) で `awscc_securityagent_application` を `resource` として書いてはいけないと決めたのと**同じ形の失敗**である — 「Terraform の外で先に成立していなければならないもの」を Terraform に書くと初回 apply が壊れる。

**有効化の手順は既存の経路に揃える** — [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) で認可を済ませた後、リポジトリ変数を足して `deploy.yml` を再実行する。
ペンテスト検証用の値（[D-030](#d-030-ペンテスト検証用の-alb-リスナールールは-phase-2-で書く)）と**まったく同じ入れ方**になるので、手順が1つで済む。**ローカル apply は使わない**（[D-009](#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)）。

**未確認のまま残る点** — DevOps Agent 側の association に渡す `service_id` の実値が分からない。
AWS アカウント紐付けはリテラル `"aws"` だと確認済みだが、GitHub 連携が何になるかは**スキーマからは読めない**。コードには暫定で `"github"` と書いてあるが、**これは確認した値ではない。** [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) で実機確認して直す。

---

## D-030: ペンテスト検証用の ALB リスナールールは Phase 2 で書く

**決定** — `var.pentest_verification_path` / `var.pentest_verification_token` と、それを返す `fixed_response` のリスナールールを、**[Phase 3](./02-implementation-plan.md#phase-3-アプリ) ではなく [Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) の `terraform/main/alb.tf` に置く**。

**理由** — 計画はこれを Phase 3（アプリ）の節に書いていたが、**実体はアプリではなく ALB のリスナールールである。**
Phase 3 は `app/` のコードを書くフェーズで、このルールは1行も TypeScript を含まない。`alb.tf` を書いている最中に同じファイルの別ルールとして足すほうが、後から `alb.tf` を開き直すより安全で、リスナーとの優先度の関係もその場で決まる。

**分割損が無いことを確認した** — 両変数の既定は `null` で、**指定されない限りリソースは1つも作られない**（`count = 0`）。
[D-007](#d-007-ドメインは決め打ちしない) の `domain_name` と同じ「未指定でも成立する任意変数」の形なので、Phase 2 に前倒ししても Phase 3・Phase 4 の内容は変わらない。

**Phase 3 に残るもの** — 無い。この項目に関して [Phase 3](./02-implementation-plan.md#phase-3-アプリ) がやることは無くなった。

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

## 未決事項

**判断事項は無い。** D-001〜D-034 で解消済み。新しい判断が生じたら D-035 以降として追記する。

### 未確認のまま残っている事実

判断ではなく、実機で確かめる項目。

- **Security Agent の無料トライアル残枠**（[Phase 0](./02-implementation-plan.md#phase-0-アカウント発行と前提確認) 項目6）— CLI からは取得できなかった。コンソールで確認する。**ペンテスト実行前に必ず**（[D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ)）
  → **トライアルの「期間」は制約にならない**（[D-011](#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy) で1週間以内に全削除する方針が決まったため、2ヶ月枠の内側に収まる）。
  **確認が要るのは「残枠」のほう。** 使い切っていればペンテスト1回 $50/task-hour が実費になり、[D-015](#d-015-予算上限は月-100通知は管理アカウントのメールへ) の上限 $100 の半分を消費しうる
- **`devops-agent get-account-usage` が `AccessDenied` になる理由** — 同じ `aidevops` 名前空間の他 API は通るので名前空間ごとの deny ではない。仮説は①オンボード前は使えない ②使用量は請求データなので管理アカウント側にしか出ない ③ルートユーザー固有の制限。
  **2026-08-03 に Security Agent を有効化した後も `AccessDenied` のままだった**が、これは①を否定しない — **`get-account-usage` は `devops-agent` の API であり、DevOps Agent 側の Agent Space はまだ存在しない**ため。[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) で DevOps Agent の Agent Space を作った後に再試行すれば①を切り分けられる
- **コストデータに実際の課金が乗ってくるか** — [Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) で再実行したが**まだ判定できない**。`ce:GetCostAndUsage` は正常に応答するものの金額は `0` のままで、これは①反映遅延 ②Phase 1 のリソースの請求額がそもそもほぼゼロ、で説明がつく。
  → **インフラが実際に稼働した後でなければ測れない。[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) の項目11 で確認する**
- **DevOps Agent の GitHub 連携を Terraform でどこまで書けるか**（[awscc プロバイダのスキーマ検証](#awscc-プロバイダのスキーマ検証phase-0-項目5) を参照）。[Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) で確認する。
  → **[Phase 2](./02-implementation-plan.md#phase-2-インフラ本体を書く) で書く口だけは用意した**（[D-029](#d-029-エージェントの-github-連携は既定で無効にする)、既定は無効）。
  **`awscc_devopsagent_association` に渡す GitHub 用の `service_id` の実値は依然として不明で、コード中の `"github"` は確認した値ではない**
- **`UnHealthyHostCount` のアラームが、トラフィックの無い時間帯に ALARM へ落ちるか** — [D-028](#d-028-異常ホストアラームは-minimum-統計で見る) で `breaching` の代償として引き受けたが、**実際の振れ方は文書からの予測であって実測ではない。** [Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) で観測する
- **サービスの `MemoryUtilization` の分母が、タスク単位の 512 MiB とコンテナ単位の hard limit のどちらか** — [D-034](#d-034-観点-1-2-と-1-6-の想定症状を訂正する) の通り**公式ドキュメントからは決まらない。** 観点1-4 でメモリアラームが鳴るかがこれで変わる（設計自体はどちらでも成立する）。[Phase 6](./02-implementation-plan.md#phase-6-受け入れ確認) で実測する
- **観点1-5 で確実にスロットリングを起こす負荷条件** — 低容量プロビジョンド（1 WCU）に落とした後、どれだけの送信で `WriteThrottleEvents` が立つかは決めていない。故障を実際に仕込むときに詰める（[D-005](#d-005-故障は今は仕込まないただし3観点の余地を設計に残す) の範囲外）
- **`awscc_securityagent_target_domain` で HTTP_ROUTE 検証まで完了できるか** — 検証パスとトークンは computed 属性で読めるが、検証の完了を Terraform が待てるかは不明。成立すれば [Phase 5](./02-implementation-plan.md#phase-5-エージェント接続) のブラウザ操作が1つ減る
