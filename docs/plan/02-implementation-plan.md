# 実装計画

決定の根拠は [00-decisions.md](./00-decisions.md)、故障の仕込み先は [01-fault-perspectives.md](./01-fault-perspectives.md)、用語は [CONTEXT.md](../../CONTEXT.md) を参照。

---

## 全体像

```
Phase 0  アカウント発行と前提確認        ← 手作業（ユーザー）＋検証
Phase 1  ブートストラップ ＋ 最小 CI     ← ローカルから1回だけ apply
Phase 2  インフラ本体を書く              ← plan まで。apply はしない
Phase 3  アプリ
Phase 4  CI/CD の拡充                    ← ★ main/ の初回 apply はここ
Phase 5  エージェント接続                ← 一部ブラウザ操作が残る
Phase 6  受け入れ確認
```

Phase 1 だけがローカル apply で、`terraform/main/` はすべて CI 経由で apply される。
この境目は「**CI が動くために必要なものは CI では作れない**」という制約から来ている。

**なぜ Phase 2 で apply しないのか** — `terraform/main/` には ECS サービス（desired = 2）が含まれる。
アプリの実装は Phase 3、イメージの build & push は Phase 4 なので、**Phase 2 の時点で apply すると ECR が空のままタスクが起動を試み、2台とも pull に失敗し続ける。**
`deploy.yml` は「build & push → apply」の順で走るため、**初回デプロイの時点で初めてイメージとインフラが揃う。**
これは [D-009](./00-decisions.md#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)（デプロイ = terraform apply）から自然に出てくる順序であって、回避策ではない。

**Phase 1 に「最小 CI」が含まれる理由** — Phase 1 の完了条件は「CI が OIDC でこのアカウントに入り、S3 の state を読める」こと。
**これを確かめる手段自体が CI である**ため、疎通確認用の最小ワークフローをここで作る。
OIDC の信頼ポリシーや state の権限は間違えやすく、Terraform を大量に書いた後で発覚すると手戻りが大きい。
Phase 4 はその最小版に、build & push・plan の PR コメント・デプロイ完了待ちを**足す**フェーズになる。

---

## リポジトリ構成

`OR-Sasaki/devops-agent-form`（Public）のモノレポ。

```
devops-agent-form/
├── README.md                      警告を冒頭に大書き（D-010 緩和策1）
├── CONTEXT.md                     用語集
├── .gitignore                     ★ *.tfstate / *.tfstate.backup / .terraform/ / *.tfvars
├── docs/plan/                     この計画一式
│
├── terraform/
│   ├── bootstrap/                 ローカルから1回。state はローカル
│   │   ├── versions.tf
│   │   ├── providers.tf           aws login のプロファイルを指定（D-016。assume_role は使わない）
│   │   ├── state.tf               Terraform state 用 S3 バケット
│   │   ├── oidc.tf                GitHub OIDC プロバイダ＋Actions 用ロール
│   │   ├── ecr.tf                 ECR（main を destroy しても残す）
│   │   ├── cloudtrail.tf          設定変更の追跡（観点1に必須）＋ 証跡ログ用 S3 バケット
│   │   ├── budget.tf              予算アラート（月 $100 / D-015）
│   │   └── variables.tf
│   │
│   └── main/                      CI が apply。state は S3
│       ├── versions.tf            aws ＋ awscc（>= 1.66.0）
│       ├── providers.tf
│       ├── backend.tf             S3 ＋ use_lockfile = true
│       ├── network.tf             VPC / public subnet ×2 / IGW / SG
│       ├── alb.tf
│       ├── ecs.tf
│       ├── dynamodb.tf
│       ├── observability.tf       ロググループ / アラーム / Container Insights
│       ├── devops-agent.tf        awscc_devopsagent_agent_space ＋ association
│       ├── security-agent.tf      awscc_securityagent_agent_space ＋ IAM
│       ├── fault-injection.tf     観点1の切り替え口（今は none 固定）
│       └── variables.tf
│
├── app/
│   ├── src/
│   │   ├── index.tsx              ルーティング
│   │   ├── submit.ts              ★ 入力処理を集約（観点2・3の仕込み先）
│   │   ├── admin.tsx              一覧表示（観点3-1 / 3-4 の仕込み先）
│   │   ├── db.ts                  DynamoDB アクセス
│   │   └── logger.ts              構造化 JSON ログ
│   ├── package.json / tsconfig.json
│   └── Dockerfile                 マルチステージ / node:22-slim
│
└── .github/workflows/
    ├── pr.yml                     lint / typecheck / test / build ＋ terraform plan（Phase 4）
    └── deploy.yml                 Phase 1 で最小版（OIDC → terraform init / plan）を作り、
                                   Phase 4 で build&push・apply・デプロイ完了待ちを足す
```

---

## Phase 0: アカウント発行と前提確認

**進捗（2026-08-03 時点）— 項目6 を除いて完了**

| # | 項目 | 状態 |
|---|---|---|
| 1 | デモアカウントの発行 | ✅ **完了** — `308513050613`。既存リソースはゼロ |
| 2 | デモアカウントに Terraform から入れること | ✅ **完了** — `aws login` ＋ `credential_process`。S3 バックエンドで state 書き込みまで実測（[D-016](./00-decisions.md#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない)） |
| 3 | SCP が必要な API を弾かないこと | ✅ **完了** — `ecs` / `elasticloadbalancing` / `dynamodb` / `aidevops` / `securityagent` すべて通る |
| 4 | Fargate の vCPU クォータ | ✅ **完了** — 6 vCPU（必要 0.5） |
| 5 | `awscc` のリソース名の実在確認 | ✅ **完了** — 3つとも実在 |
| 6 | Security Agent の無料トライアル残枠 | 🚧 **未確認** — CLI から取得できず。コンソールで確認する |
| 7 | デモアカウントからコストデータが見えること | ✅ **完了** — `ce:GetCostAndUsage` が正常応答 |

実測値の詳細は [00-decisions.md の「Phase 0 の実機確認結果」](./00-decisions.md#phase-0-の実機確認結果デモアカウント-308513050613) にある。

> **サインインしているのはルートユーザー**（`arn:aws:iam::308513050613:root`）。
> [D-018](./00-decisions.md#d-018-terraform-はルートユーザーのまま回す) で**このまま進めると決定済み**。専用アカウントなので爆発半径は閉じており、`aws login` は長期アクセスキーを作らないため [D-004](./00-decisions.md#d-004-手作業はアカウント発行のみ以降すべて-terraform) の核心は保たれる。
> ただしルートは IAM ポリシーで制限できないので、**ルートに MFA を設定しておくこと。**

---

**1. アカウント発行（ユーザーの手作業）— 完了**

管理アカウント **<ç®¡çã¢ã«ã¦ã³ã ID>** から発行済み。アカウント ID は **308513050613**。

**2. デモアカウントに Terraform から入れること**

> **[D-016](./00-decisions.md#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) で方式が変わった。** 当初は「`OrganizationAccountAccessRole` を管理アカウントから assume する」計画だったが、**管理アカウントの認証情報がローカルに無く前提が成立しなかった**ため、`aws login` でデモアカウントへ直接入る方式に変更した。

```
aws login --remote --profile devopsagent
```

確認すること — `aws sts get-caller-identity --profile devopsagent` が `308513050613` を返し、`aws configure list --profile devopsagent` の TYPE 列が `login` になっていること。
TYPE が `shared-credentials-file` だと静的キーに負けている（[D-016](./00-decisions.md#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない)）。

**結果 ✅** — 両方確認。加えて Terraform 経路も実測した。

- プロバイダのみなら `devopsagent` プロファイルでそのまま apply が通る
- **S3 バックエンドを使う場合は `devopsagent-tf`（`credential_process`）が必須。** `devopsagent` では `No valid credential sources found` で init が落ちる
- `credential_process` は **`/opt/homebrew/bin/aws` と絶対パス**で書く。詳細は [D-016](./00-decisions.md#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない)

**3. SCP が `ecs:*` / `elasticloadbalancing:*` / `dynamodb:*` / `aidevops:*` / `securityagent:*` を弾かないこと**

弾いていた場合、原因の分かりにくい apply 失敗になるのでここで潰す。

> **確認方法が変わった。** SCP の内容を読む API（`organizations:DescribePolicy` 等）は**管理アカウント専用**で、[D-016](./00-decisions.md#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) では届かない。
> 代わりに**デモアカウント側から実効性で確認する** — 各サービスの API を実際に叩いて `AccessDenied`（SCP 由来）が返らないことを見る。
> **SCP はメンバーアカウントの root にも適用される**ことが公式ドキュメントで確認できているため、この方法で判定できる（[00-decisions.md](./00-decisions.md#phase-0-の実機確認結果デモアカウント-308513050613) に原文を引用）。

**結果 ✅** — `ecs` / `elasticloadbalancing` / `dynamodb` / `aidevops` / `securityagent` すべて通った。

**読み取りと作成を別々に測っている。** SCP は Action 単位で拒否できるため、`ListClusters` が通ることは `CreateCluster` が通ることを意味しない。
`ecs:CreateCluster` / `dynamodb:CreateTable` / `ecr:CreateRepository` / `iam:CreateRole` / `logs:CreateLogGroup` / `s3:CreateBucket` は**実際に作成して削除**し、
`elasticloadbalancing` / `aidevops` / `securityagent` / `cloudtrail` / `budgets` / `ec2` は**無効パラメータを渡して認可だけ**を確認した（`AccessDenied` ではなくパラメータエラーが返る）。
全結果は [00-decisions.md](./00-decisions.md#phase-0-の実機確認結果デモアカウント-308513050613) にある。

唯一 `devops-agent get-account-usage` だけ `AccessDenied` になるが、同名前空間の他 API は通るため名前空間ごとの deny ではない（原因は [未決事項](./00-decisions.md#未確認のまま残っている事実) に記載）。

**4. Fargate の vCPU クォータが新規アカウントの初期値で足りること**

`desired = 2` × 0.25 vCPU（[D-013](./00-decisions.md#d-013-委任された技術判断こちらで決定)）が通ること。

**結果 ✅** — **Fargate On-Demand vCPU resource count = 6**。必要量は 0.5 なので十分。ALB も 50/リージョンで足りる。

**5. `awscc` プロバイダのリソース名の実在確認 — 完了**

`awscc_devopsagent_agent_space` / `awscc_devopsagent_association` / `awscc_securityagent_agent_space` は **3つとも実在**（awscc v1.95.0 のスキーマを直接検査）。
**[Phase 5](#phase-5-エージェント接続) の作り直しリスクは消滅した。**

詳細と、計画に書かれていなかった追加の発見（`awscc_securityagent_target_domain` が検証トークンを computed 属性で返す、`awscc_devopsagent_association` に `service_id` が必須、IAM ロールが2つ要る、`time_sleep` 30秒が要る等）は
[00-decisions.md の「awscc プロバイダのスキーマ検証」](./00-decisions.md#awscc-プロバイダのスキーマ検証phase-0-項目5) に記載。

**6. Security Agent の無料トライアル残枠**

ペンテストは $50/task-hour（[D-015](./00-decisions.md#d-015-予算上限は月-100通知は管理アカウントのメールへ)）。1回で予算上限の半分を消費しうる。

**結果 🚧 未確認** — CLI から取得する手段が見つからなかった。`devops-agent get-account-usage` は `AccessDenied`、`securityagent` には使用量系 API が無く、`freetier get-free-tier-usage` は空を返す。
→ **コンソールで確認する。** [Phase 5](#phase-5-エージェント接続) の項目4 でペンテスト実行直前に必ず見ることになるので、そこが実質的な確認ポイントになる。
**残枠が読めないままペンテストを実行してはいけない。**

> **トライアルの「期間」は制約から外れた** — [D-011](./00-decisions.md#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy) で **1週間以内に全削除**する方針が決まったため、2ヶ月の枠に確実に収まる。
> **確認が要るのは「残枠」のほう。** 使い切っていれば期間内でもペンテストは $50/task-hour の実費になる。

**7. デモアカウントからコストデータが見えること**

[D-003](./00-decisions.md#d-003-専用の新規-aws-アカウントを発行する) の通り請求は管理アカウントに集約される。
メンバーアカウント自身の Budgets は作れるが、**Cost Explorer のリンクアカウントアクセスは管理アカウント側の設定**（Cost Management preferences）で制御される。
ここが無効だと [D-015](./00-decisions.md#d-015-予算上限は月-100通知は管理アカウントのメールへ) の予算アラートがデータを拾えない。

> **[D-016](./00-decisions.md#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない) により、設定そのものは確認できない。** デモアカウント側から `ce:GetCostAndUsage` を叩き、**データが返るかどうかで判定する**。返らなければ管理アカウント側での有効化が別途必要になる。

**結果 ✅** — `ce:GetCostAndUsage` が正常応答（`ResultsByTime` / `Estimated: true`）。権限が無ければ `AccessDeniedException` が返るはずなので、リンクアカウントアクセスは有効と判断してよい。
金額は $0 だが、これはアカウントが新品で支出が無いため。**実際の課金が乗ってくるかは [Phase 1](#phase-1-ブートストラップ--最小-ci) 以降に再確認する。**

> **削除済み** — 以前あった「自動修復 PR が ap-northeast-1 で使えるか」の確認は不要になった。
> 自動修復はリージョンではなくリポジトリ可視性で決まり、かつ [D-014](./00-decisions.md#d-014-security-agent-の自動修復はスコープ外) でスコープ外としたため。

> **Phase 0 で判明した仕様（計画に反映済み）** — DevOps Agent は **PR を作らない**。目標2 の到達点は [D-017](./00-decisions.md#d-017-目標2-の到達点を-agent-ready-specification-に縮小する) で agent-ready specification に縮小した。

**完了条件** — **項目1〜5・7 が確認済みで、デモアカウントに Terraform から入れる状態。** → **達成済み（2026-08-03）。**

> **項目6（Security Agent の無料トライアル残枠）は完了条件から明示的に外し、[Phase 5](#phase-5-エージェント接続) の事前条件に移した。**
>
> 理由 — CLI から取得する手段が存在せず、Phase 0 の時点では確認できない。
> かつ**この項目が守っているのはペンテスト実行時のコスト**であり、ペンテストは [Phase 5](#phase-5-エージェント接続) まで実行しない。
> Phase 5 の項目4 が「実行直前に残枠を確認する」を既に要求しているため、**そこが唯一かつ実効的なゲートになる。**
>
> **Phase 1〜4 の進行を妨げない。** ただし残枠が読めないままペンテストを実行してはいけない、という制約は生きている。

---

## Phase 1: ブートストラップ ＋ 最小 CI

`terraform/bootstrap/` を**ローカルから1回だけ** apply する。state はローカル保持（この層は CI から触らない）。

> **使うプロファイル** — `bootstrap/` は state がローカルなので **`devopsagent`** でよい（S3 バックエンドを使わないため）。
> 一方 `terraform/main/` をローカルから plan するときは **`devopsagent-tf`**（`credential_process`）が要る。[Phase 0](#phase-0-アカウント発行と前提確認) の項目2 で実測済み。
>
> この層は IAM ロールと OIDC プロバイダを作るが、**ルートユーザーのまま apply してよい**（[D-018](./00-decisions.md#d-018-terraform-はルートユーザーのまま回す)）。

| 作るもの | 目的 |
|---|---|
| S3 バケット（Terraform state 用） | バージョニング＋暗号化＋パブリックアクセスブロック |
| S3 バケット（CloudTrail 証跡用） | **state 用とは別に作る。** 証跡はバケットポリシーで CloudTrail からの書き込みを許可する必要があり、state 用と混ぜない |
| GitHub OIDC プロバイダ | `token.actions.githubusercontent.com` |
| GitHub Actions 用 IAM ロール | `sub` を `repo:OR-Sasaki/devops-agent-form:*` に**限定**する |
| ECR リポジトリ | `main/` を destroy してもイメージが残る |
| CloudTrail | 観点1で設定変更を追跡するため |
| AWS Budgets | 月 $100、実績 50/80/100% と予測 100% で通知（[D-015](./00-decisions.md#d-015-予算上限は月-100通知は管理アカウントのメールへ)） |

**あわせて作るもの（インフラではないが、この層と同時に用意する）**

- ~~**`.gitignore`**~~ — ✅ **2026-08-03 に作成済み。** `*.tfstate` / `*.tfstate.*` / `.terraform/` / `*.tfvars` に加え、**AWS コンソールのスクリーンショット**（`スクリーンショット*.png` / `Screenshot*.png`）も除外している。
  bootstrap の state は**ローカル保持**で、リポジトリは **Public**。commit するとアカウント ID・バケット名・エンドポイント URL がそのまま公開される（[D-010](./00-decisions.md#d-010-github-リポジトリは-publicor-sasakidevops-agent-form) の緩和策）
- **`deploy.yml` の最小版** — OIDC で assume し、**空の `terraform/main/` に対して `terraform init` と `plan` を通すだけ**のワークフロー。
  目的は OIDC と state の**疎通確認**であって、インフラを作ることではない（build & push・apply・デプロイ完了待ちは Phase 4 で足す）

**注意** — OIDC ロールの信頼ポリシーで `sub` を絞ること。絞らないと**任意のリポジトリからこのアカウントに入れる**。Public リポジトリなので特に重要。

**完了条件** — CI が OIDC でこのアカウントに入り、S3 の state を読み書きできること（`terraform/main/` は空のままでよい）。

---

## Phase 2: インフラ本体を書く

`terraform/main/` を**書く**フェーズ。**完了条件は `terraform plan` が通ることまで。**

`var.image_tag` はまだ実在するイメージを指せないので、**plan を通すためだけのダミー値**（`"bootstrap"` 等）を渡す。
実際の値は [Phase 4](#phase-4-cicd-の拡充) 以降、CI がコミット SHA を渡す（[D-013](./00-decisions.md#d-013-委任された技術判断こちらで決定)）。

> **`terraform/main/` の初回 apply は [Phase 4](#phase-4-cicd-の拡充) で行う。ここではしない。**
>
> この時点で ECR は空である（アプリの実装は [Phase 3](#phase-3-アプリ)、build & push は [Phase 4](#phase-4-cicd-の拡充)）。
> **イメージが存在しない状態で ECS サービスを desired = 2 で apply すると、2タスクとも ECR pull に失敗し続ける。**
> [Phase 4](#phase-4-cicd-の拡充) の `deploy.yml` は「build & push → apply」の順で走るので、**初回デプロイの時点で初めてイメージが揃う。**
> これは [D-009](./00-decisions.md#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops) の「デプロイ = terraform apply」から自然に導かれる順序であって、例外ではない。

**Phase 2 と Phase 5 の関係** — `devops-agent.tf` / `security-agent.tf` も同じ `terraform/main/` にあるため、**[Phase 4](#phase-4-cicd-の拡充) の初回 apply で Agent Space も同時に作られる。**
Terraform 上に Phase の境界は存在しない。[Phase 5](#phase-5-エージェント接続) が担当するのは、**Terraform では自動化できないブラウザ操作**（GitHub App の認可、ペンテストのターゲット検証）だけである。

**ネットワーク** — VPC `10.0.0.0/16`、**public subnet ×2**（AZ 冗長）、IGW。
**NAT Gateway は作らない**（D-002 の設計制約。作ると月$35 でアプリ本体より高い）。
SG は ALB 用（`0.0.0.0/0:80`）と ECS 用（ALB からのみ）の2つ。

**コンピュート** — ALB ＋ ターゲットグループ ＋ リスナー。ECS クラスタ、Fargate タスク定義（0.25 vCPU / 0.5 GB）、サービス（desired = 2）。

> **必須: `network_configuration { assign_public_ip = true }`**
>
> NAT Gateway を作らない構成では、**これが無いとタスクが1台も起動しない。**
> タスク ENI に Public IP が付かず、ECR からイメージを pull できず、CloudWatch Logs にも到達できないため、サービスが起動失敗を延々と繰り返す。
> 症状が[観点 1-6](./01-fault-perspectives.md#観点1-aws-設定起因)（ECR から pull できずタスク起動失敗）と同一なので、**仕込んでいない故障をデバッグする羽目になる。**
> Public IP × 2タスクの課金は [D-002](./00-decisions.md#d-002-実行基盤は-ecs-fargate--alb--dynamodb) のコスト内訳に計上済み。

**データ** — DynamoDB テーブル（オンデマンド課金）。

**可観測性 — アラームは症状ごとに必ず分離する**（01-fault-perspectives.md の要件）。
1つにまとめると Agent が症状を切り分けられず、RCA デモが成立しない。

閾値は**初期値**。デモを回しながら調整する前提だが、**未定のままでは Terraform が書けない**ので暫定値を置く。

| アラーム | メトリクス | 閾値 | 評価 | 欠損データ | 観点 |
|---|---|---|---|---|---|
| ALB 5xx 率 | `HTTPCode_ELB_5XX_Count` ＋ `HTTPCode_Target_5XX_Count` | 合計 > 5 | 5分 × 1 | `notBreaching` | 1-1 / 2-2 |
| ALB ターゲット応答時間 | `TargetResponseTime`（p95） | > 1.0 秒 | 5分 × 2 | `notBreaching` | 2-3 / 2-4 |
| ALB 異常ホスト | `UnHealthyHostCount` | >= 1 | 1分 × 2 | **`breaching`** | 1-2 / 1-3 |
| ECS CPU 使用率 | `CPUUtilization` | > 80% | 1分 × 3 | `notBreaching` | 2-3 |
| ECS メモリ使用率 | `MemoryUtilization` | > 80% | 1分 × 2 | `notBreaching` | 1-4 / 2-1 |
| DynamoDB スロットリング | `ThrottledRequests` | >= 1 | 5分 × 1 | `notBreaching` | 1-5 / 2-4 |

**異常ホストだけ `breaching`** にするのは、タスクが全滅するとメトリクス自体が欠損し、`notBreaching` では**最も重い障害が無音になる**ため。

**ECS タスク停止は CloudWatch アラームではない** — EventBridge ルール（ECS Task State Change / `lastStatus = STOPPED`）から SNS へ流す**イベント通知**であり、閾値の概念が無い。
`stoppedReason` に OOM や pull 失敗の理由が入るので、観点 1-4 / 1-6 では**アラームではなくこのイベントが根拠**になる。
調査の起点になるのは上表のアラーム側で、EventBridge は Agent が辿る痕跡として置く。

加えて Container Insights を有効化し、`var.fault_injection`（デフォルト `"none"`）を通す。
**この変数は今回は使わない。** 観点1の切り替え口を空けておくだけ（D-005）。

---

## Phase 3: アプリ

Hono ＋ TypeScript ＋ JSX、Node 22。

| ルート | 役割 |
|---|---|
| `GET /` | フォーム表示 |
| `POST /submit` | 保存。**入力処理はここに集約** |
| `GET /admin` | 送信一覧 |
| `GET /healthz` | ALB ヘルスチェック |

構造化 JSON ログにリクエスト ID と**コミット SHA** を含める。SHA が乗っていないと、Agent がログとコードを相関できない。

**ペネトレーションテストの HTTP_ROUTE 検証用の口（アプリではなく ALB 側に置く）**

[Phase 5](#phase-5-エージェント接続) のターゲットドメイン検証では、**AWS が提示するパスにトークンを配置して HTTP で取得させる**必要がある。
上のルート表にはその口が無いので、**ALB のリスナールール（`fixed_response`）で用意する。**

- `var.pentest_verification_path` / `var.pentest_verification_token`（どちらもデフォルト `null`）
- 両方が指定されたときだけ、そのパスにトークンを返すルールを**優先度を上げて**追加する
- **アプリを再デプロイせずに済む**のが利点。値は [Phase 5](#phase-5-エージェント接続) のブラウザ操作の途中で判明するため、
  **GitHub Actions のリポジトリ変数に入れて `deploy.yml` を再実行**すれば足せる（ローカル apply は使わない）

未指定なら何も作られないので、[D-007](./00-decisions.md#d-007-ドメインは決め打ちしない) の「未指定でも ALB の DNS 名でそのまま動く」と同じ扱いになる。

---

## Phase 4: CI/CD の拡充

[Phase 1](#phase-1-ブートストラップ--最小-ci) で作った最小 `deploy.yml`（OIDC 疎通確認のみ）に、**ビルドと apply を足す**フェーズ。ゼロから作るのではない。

**このフェーズの初回実行が `terraform/main/` の初回 apply になる。**
ネットワーク・ALB・ECS・DynamoDB・アラーム・Agent Space がここで初めて実体化し、**同時にイメージも揃うのでタスクが起動できる。**
[Phase 0](#phase-0-アカウント発行と前提確認) で潰しきれなかった SCP やクォータの問題があれば、ここで露見する。

**`pr.yml`**（新規）— app の lint / typecheck / test / build と、terraform の fmt / validate / plan。plan 結果を PR にコメント。

**`deploy.yml`**（`main` push / Phase 1 から拡張）— 順序が重要。

```
OIDC で assume
  ↓
docker build & push  （タグ = コミット SHA）
  ↓
terraform apply -var image_tag=<SHA>     ← Terraform がイメージタグを所有
                -var pentest_verification_path=${{ vars.PENTEST_VERIFICATION_PATH }}
                -var pentest_verification_token=${{ vars.PENTEST_VERIFICATION_TOKEN }}
  ↓
ECS デプロイ完了を待つ
```

ペンテスト検証用の2変数は**未設定なら空**で、その場合は対応する ALB リスナールールが作られない（[Phase 3](#phase-3-アプリ)）。
[Phase 5](#phase-5-エージェント接続) でリポジトリ変数に値を入れて再実行したときだけ、検証用の口が開く。**これにより apply 経路を CI 1本に保てる。**

**この順序である理由** — Terraform にイメージタグを所有させることで drift が出ない。
そして「**デプロイ = terraform apply**」になるため、観点1（AWS 設定起因）と観点2（コード起因）が**同じ1本のデプロイイベント**として Agent から見える。RCA デモが自然に成立する。

先に push しておかないと apply 時点でイメージが存在しないので、build&push が先。

**長期アクセスキーは一切使わない。** OIDC のみ（D-009）。

---

## Phase 5: エージェント接続

**DevOps Agent**（Terraform）— `awscc_devopsagent_agent_space` ＋ `awscc_devopsagent_association`（アカウント紐付け）。CloudWatch は同一アカウントなら追加接続不要。
AWS 公式サンプル [aws-samples/sample-aws-devops-agent-terraform](https://github.com/aws-samples/sample-aws-devops-agent-terraform) を下敷きにする。

[Phase 0](#phase-0-アカウント発行と前提確認) のスキーマ検証で判明した必須事項（詳細は [00-decisions.md](./00-decisions.md#awscc-プロバイダのスキーマ検証phase-0-項目5)）:

- `awscc_devopsagent_association` は **`service_id` が必須**。AWS アカウント紐付けではリテラル `"aws"`、`account_type` は `"monitor"`
- **IAM ロールが2つ要る** — Agent Space 用（`AIDevOpsAgentAccessPolicy`）と Operator App 用（`AIDevOpsOperatorAppAccessPolicy`）。どちらも `aidevops.amazonaws.com` を信頼し、Operator App 側は `sts:TagSession` も許可する
- **IAM 作成と Agent Space 作成の間に `time_sleep` 30秒**を挟む。Agent Space 作成時に信頼ポリシーが検証されるため、伝播前だと失敗する
- **GitHub 連携は Terraform で完結しない可能性が高い** — `awscc_devopsagent_service.service_details` に `git_hub` が無く、AWS 公式 Terraform ガイドの対応連携一覧にも GitHub は含まれない（GitLab はある）。ここは実機で確認する

**Security Agent**（Terraform）— `awscc_securityagent_agent_space`、`SecurityAgentAppRole-*`、`SecurityAgentServiceRole-*`。
AWS 公式サンプル [aws-samples/sample-terraform-for-security-agent](https://github.com/aws-samples/sample-terraform-for-security-agent) を下敷きにする。

> **`awscc_securityagent_application` は Terraform で作らない。** Application は**アカウントに1つ**で、2026-08-03 にコンソールで有効化済み（[D-019](./00-decisions.md#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる)）。
> `resource` として書くと state に無い既存 Application と重複し、**apply が失敗する。**
>
> **Agent Space は Application を参照しない**（`awscc_securityagent_agent_space` に application 系の属性は存在しない — スキーマで確認済み）ため、そもそも参照は不要。
> 万一 ID が要るときは**読み取り専用の data source `awscc_securityagent_application` / `awscc_securityagent_applications`** が使える。

`awscc_securityagent_agent_space` は GitHub リポジトリ接続を属性として持つ（`integrated_resources.provider_resources.git_hub_repository{owner,name}` と `git_hub_capabilities{leave_comments, remediate_code}`）。
**`remediate_code` は `false` にする** — [D-014](./00-decisions.md#d-014-security-agent-の自動修復はスコープ外) で自動修復をスコープ外としているため。

> **Security Agent は 2026-08-03 にコンソールから先行して有効化済み。**
>
> 既に存在するもの — Application `app-966a2407-...`（`SecurityAgent`）と Agent Space `as-d363b56d-...`（**`SandboxAgent`**、ap-northeast-1）。
>
> **[D-019](./00-decisions.md#d-019-先行作成した-agent-space-は削除しterraform-に作り直させる) で扱いは決定済み** — **Agent Space は削除して Terraform に作り直させる。`import` はしない。Application は残す。**
> 削除は手作業で行うが、**残っていても作業を止めない。** Terraform が作るときに名前が衝突したら、そのとき消せばよい。

**ここだけ手作業が残る（ブラウザ操作が必須）**

1. GitHub App の認可 — DevOps Agent 側、Security Agent 側それぞれ
2. **リポジトリ選択は必ず "Only select repositories"** で `devops-agent-form` のみ
   → "All" を選ぶと既存 27 リポジトリ全部がスコープに入る（D-006）
3. ペネトレーションテストのターゲットドメイン登録（ALB の DNS 名）と **HTTP_ROUTE 検証**
   → 提示されたパスとトークンを **GitHub Actions のリポジトリ変数**（`PENTEST_VERIFICATION_PATH` / `PENTEST_VERIFICATION_TOKEN`）に設定し、
     `deploy.yml` を再実行して apply する（[Phase 3](#phase-3-アプリ) の ALB リスナールールが立つ）

   > **Terraform で完結できる可能性がある（[Phase 0](#phase-0-アカウント発行と前提確認) の発見・要実機確認）。**
   > `awscc_securityagent_target_domain` は `verification_details.http_route.route_path` と `.token` を **computed 属性として返す**。
   > つまりターゲットドメイン登録を Terraform で行えば、検証用のパスとトークンを**リポジトリ変数を経由せず ALB リスナールールへ直接渡せる**。
   > 手作業とブラウザ操作が丸ごと消え、[Phase 3](#phase-3-アプリ) の `var.pentest_verification_path` / `var.pentest_verification_token` も不要になる。
   > **ただし「検証の完了」まで Terraform が待てるかは未確認**（`verification_status` は computed で、検証を発火させる別の API があるかもしれない）。実機で確かめてから採用を決める
   → **ローカルから `terraform apply` しない。** `terraform/main/` の apply 経路は CI 1本に保つ（[D-009](./00-decisions.md#d-009-アプリも-terraform-も-ci-から-apply-する完全-gitops)）
   → トークンは ALB 上で**公開配信される値**なので Secrets ではなく Variables でよい
   → キャンペーン型（D-011）なので期間中は 1 回で済む
4. **ペンテストを実行する直前に、無料トライアルの残枠を確認する**（[D-015](./00-decisions.md#d-015-予算上限は月-100通知は管理アカウントのメールへ)）
   → **$50 / task-hour** で、1回で予算上限 $100 の半分を消費しうる。[Phase 0](#phase-0-アカウント発行と前提確認) でも確認するが、構築期間中に枠が減っている可能性があるため**実行直前にもう一度見る**

**注意 — GitHub App の単一インストール制約は2つのエージェントで異なる。まとめて扱わないこと。**

| | 制約 | 出典 |
|---|---|---|
| **Security Agent** | **1つの AWS アカウントに固定される。** 「A GitHub App can only be installed once to a GitHub account or GitHub organization. If you need to connect the same GitHub organization to AWS Security Agent, you must use the same AWS account where the integration was first registered.」 別アカウントで使うにはアンインストールが必要 | [Connect to GitHub](https://docs.aws.amazon.com/securityagent/latest/userguide/connect-github.html) |
| **DevOps Agent** | **複数の AWS アカウント・リージョンから同じ GitHub アカウントに接続できる**（2026-06-30 に対応）。「If the AWS DevOps Agent GitHub App is already installed, additional accounts and Regions reuse the existing installation, so you don't need to reinstall it.」 | [What's new](https://docs.aws.amazon.com/devopsagent/latest/userguide/whats-new.html) |

本プロジェクトは両方を同じデモアカウントに紐づけるため**実害は無い**が、Security Agent 側だけは
**`OR-Sasaki` を他の AWS アカウントで使えなくなる**点が残る。撤収時にアンインストールするかはそのとき判断する。

---

## Phase 6: 受け入れ確認

**故障は仕込まない**（D-005）。確認するのは「**後から仕込める状態になっているか**」。

| # | 確認項目 |
|---|---|
| 1 | **ECS タスクが 2台とも起動し、ECR の pull と CloudWatch Logs への送信が成功している**（`assign_public_ip` の検証。ここが通らないと以降は全て見られない） |
| 2 | フォームが動き、送信内容が DynamoDB に入り、`/admin` に出る |
| 3 | DevOps Agent のコンソールにトポロジー（ALB → ECS → DynamoDB）が出る |
| 4 | アラームが**症状ごとに分かれて**存在し、閾値と欠損データ設定が入っている |
| 5 | CloudTrail に設定変更が記録される（観点1の前提） |
| 6 | `var.fault_injection` の口が通っている（観点1の前提） |
| 7 | コミット SHA が**構造化ログ・イメージタグ・ECS タスク定義**の3箇所に残り、アラーム → ログ → コミットが辿れる（観点2の前提） |
| 8 | GitHub が DevOps Agent と Security Agent の**両方**に接続済み（観点2・3の前提） |
| 9 | ペンテストのターゲット検証が完了している（観点3の前提） |
| 10 | PR を出すと Security Agent がコードレビューコメントを付ける |
| 11 | **日次の実績が [D-002](./00-decisions.md#d-002-実行基盤は-ecs-fargate--alb--dynamodb) の見積り（1日 約 $1.8）の範囲に収まっている**ことを Cost Explorer で確認し、[D-015](./00-decisions.md#d-015-予算上限は月-100通知は管理アカウントのメールへ) の予算アラートが設定済み |

**項目11 が「月額」ではなく「日次」なのはなぜか** — [D-011](./00-decisions.md#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy) で検証期間を約1週間としたため、**1ヶ月分の請求は決して発生しない。**
「月 $55 の範囲に収まるか」では受け入れ判定ができないので、日次の実績で見る。

**項目10の判定基準** — [D-005](./00-decisions.md#d-005-故障は今は仕込まないただし3観点の余地を設計に残す) で故障を仕込まないため、この時点のコードに脆弱性は無い。
Security Agent は**指摘ゼロのときも `No issues identified.` とコメントする**ので、**このコメントが付けば合格**。
「コメントが付かない」は「問題が無い」ではなく**接続できていない**を意味する、と読める点がこの項目の価値。

**⚠️ draft PR では発火しない。** コードレビューは PR を **「Ready for review」にした時点**でトリガーされる。
draft のまま待つと何も起きず、**接続できていないのと区別がつかない。** この項目を確認するときは必ず draft を解除すること。

---

## コストと撤収

**コスト**

**検証期間は 2026-08-03 から1週間以内**（[D-011](./00-decisions.md#d-011-撤収はキャンペーン型検証期間中は起動しっぱなし期間後に-destroy)）。遅くとも **2026-08-10 頃までに `terraform destroy`** する。

| 項目 | 金額 |
|---|---|
| インフラ | **1週間で約 $13**（月額換算 約 $55）。内訳は [D-002](./00-decisions.md#d-002-実行基盤は-ecs-fargate--alb--dynamodb) |
| DevOps Agent | $0.0083 / agent-second。無料トライアル2ヶ月 |
| Security Agent ペンテスト | **$50 / task-hour**。無料トライアルあり（**残枠は要確認**） |
| 予算アラート | 月 $100 で通知（[D-015](./00-decisions.md#d-015-予算上限は月-100通知は管理アカウントのメールへ)） |

インフラ内訳の要点は、**Fargate が 2タスク分**（[D-013](./00-decisions.md#d-013-委任された技術判断こちらで決定) の desired = 2）であることと、**NAT を使わない代償として Public IPv4 が4アドレス分**（タスク ×2 ＋ ALB ノード ×2）かかること。
ALB の LCU・CloudWatch Logs・Container Insights・CloudTrail 保存は上記に含まれないため、実際はもう少し上振れする。

ペンテストが最も高額。無料枠内で回す前提とし、Phase 5 で残枠を確認してから実行する。

**撤収手順**

1. `terraform/main/` を destroy（ALB / ECS / DynamoDB / Agent Space が消える）
2. 必要なら `terraform/bootstrap/` も destroy（state バケット・ECR・CloudTrail）
3. 他アカウントで Security Agent を使う予定があるなら、**GitHub App をアンインストール**する
4. デモアカウント自体を閉鎖する場合は管理アカウントから

---

## 主なリスク

| リスク | 対応 |
|---|---|
| ~~**`awscc` のリソース名が想定と違う**~~ | ✅ **解消。** [Phase 0](#phase-0-アカウント発行と前提確認) の項目5 で3つとも実在を確認した |
| **`aws login` の認証情報を S3 バックエンドが読めない** | Terraform 1.13.0 では未対応。`credential_process` を橋渡しに使う（[D-016](./00-decisions.md#d-016-デモアカウントへは-aws-login-で直接入る管理アカウントは経由しない)）。CI は OIDC なので影響しない |
| **`assign_public_ip` の指定漏れでタスクが起動しない** | Phase 2 に必須要件として明記。Phase 6 の項目1 で最初に確認する |
| SCP が apply を弾く | Phase 0 で事前確認 |
| Push Protection が観点3-3 を阻む | ダミー値を使う、または Security Agent の指摘のみに絞る（D-010） |
| 脆弱なエンドポイントの公開 | キャンペーン型で期間限定（D-011）、README で警告（D-010） |
| CI が実質 Administrator 権限を持つ | 専用アカウントで爆発半径を閉じる（D-003）。OIDC の `sub` を厳密に絞る |
