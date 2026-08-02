# 実装計画

決定の根拠は [00-decisions.md](./00-decisions.md)、故障の仕込み先は [01-fault-perspectives.md](./01-fault-perspectives.md)、用語は [CONTEXT.md](../../CONTEXT.md) を参照。

---

## 全体像

```
Phase 0  アカウント発行と前提確認        ← 手作業（ユーザー）＋検証
Phase 1  ブートストラップ                ← ローカルから1回だけ apply
Phase 2  インフラ本体                    ← 以降 CI が apply
Phase 3  アプリ
Phase 4  CI/CD
Phase 5  エージェント接続                ← 一部ブラウザ操作が残る
Phase 6  受け入れ確認
```

Phase 1 だけがローカル apply で、Phase 2 以降はすべて CI 経由になる。
この境目は「**CI が動くために必要なものは CI では作れない**」という制約から来ている。

---

## リポジトリ構成

`OR-Sasaki/devops-agent-form`（Public）のモノレポ。

```
devops-agent-form/
├── README.md                      警告を冒頭に大書き（D-010 緩和策1）
├── CONTEXT.md                     用語集
├── docs/plan/                     この計画一式
│
├── terraform/
│   ├── bootstrap/                 ローカルから1回。state はローカル
│   │   ├── versions.tf
│   │   ├── providers.tf           管理アカウント → OrganizationAccountAccessRole を assume
│   │   ├── state.tf               Terraform state 用 S3 バケット
│   │   ├── oidc.tf                GitHub OIDC プロバイダ＋Actions 用ロール
│   │   ├── ecr.tf                 ECR（main を destroy しても残す）
│   │   ├── cloudtrail.tf          設定変更の追跡（観点1に必須）
│   │   ├── budget.tf              予算アラート
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
    ├── pr.yml                     lint / typecheck / test / build ＋ terraform plan
    └── deploy.yml                 build&push → terraform apply → デプロイ完了待ち
```

---

## Phase 0: アカウント発行と前提確認

**ユーザーが行う作業（唯一の手作業）**

1. 管理アカウント **<ç®¡çã¢ã«ã¦ã³ã ID>** で新規メンバーアカウントを `CreateAccount`
   - メールは Gmail のプラスエイリアスで足りる（例: `<ç®¡çã¢ã«ã¦ã³ãã®ã¡ã¼ã«ã¢ãã¬ã¹>`）
   - 発行後、**アカウント ID を控える**

**発行後にこちらで確認すること（credential が通り次第）**

2. `OrganizationAccountAccessRole` を assume できること
3. **配置先 OU の SCP** が `ecs:*` / `elasticloadbalancing:*` / `dynamodb:*` / `aidevops:*` / `securityagent:*` を弾いていないこと
   → 弾いていた場合、原因の分かりにくい apply 失敗になるのでここで潰す
4. **Fargate の vCPU クォータ** が新規アカウントの初期値で足りること
5. **[D-008 のリスク検証] Security Agent の自動修復 PR が ap-northeast-1 で使えるか**
   → 使えなければ Security Agent の Agent Space だけ us-east-1 へ（逃げ道は D-008 に記載）

**完了条件** — 上記すべてが確認済みで、デモアカウントに Terraform から入れる状態。

---

## Phase 1: ブートストラップ

`terraform/bootstrap/` を**ローカルから1回だけ** apply する。state はローカル保持（この層は CI から触らない）。

| 作るもの | 目的 |
|---|---|
| S3 バケット（Terraform state 用） | バージョニング＋暗号化＋パブリックアクセスブロック |
| GitHub OIDC プロバイダ | `token.actions.githubusercontent.com` |
| GitHub Actions 用 IAM ロール | `sub` を `repo:OR-Sasaki/devops-agent-form:*` に**限定**する |
| ECR リポジトリ | `main/` を destroy してもイメージが残る |
| CloudTrail | 観点1で設定変更を追跡するため |
| AWS Budgets | 予算超過の通知 |

**注意** — OIDC ロールの信頼ポリシーで `sub` を絞ること。絞らないと**任意のリポジトリからこのアカウントに入れる**。Public リポジトリなので特に重要。

**完了条件** — CI が OIDC でこのアカウントに入り、S3 の state を読めること。

---

## Phase 2: インフラ本体

`terraform/main/`。以降は CI が apply する。

**ネットワーク** — VPC `10.0.0.0/16`、**public subnet ×2**（AZ 冗長）、IGW。
**NAT Gateway は作らない**（D-002 の設計制約。作ると月$35 でアプリ本体より高い）。
SG は ALB 用（`0.0.0.0/0:80`）と ECS 用（ALB からのみ）の2つ。

**コンピュート** — ALB ＋ ターゲットグループ ＋ リスナー。ECS クラスタ、Fargate タスク定義（0.25 vCPU / 0.5 GB）、サービス（desired = 2）。

**データ** — DynamoDB テーブル（オンデマンド課金）。

**可観測性 — アラームは症状ごとに必ず分離する**（01-fault-perspectives.md の要件）。
1つにまとめると Agent が症状を切り分けられず、RCA デモが成立しない。

| アラーム | 対応する観点 |
|---|---|
| ALB 5xx 率 | 1-1 / 2-2 |
| ALB ターゲット応答時間 | 2-3 / 2-4 |
| ALB `UnHealthyHostCount` | 1-2 / 1-3 |
| ECS CPU 使用率 | 2-3 |
| ECS メモリ使用率 | 1-4 / 2-1 |
| ECS タスク停止（EventBridge 経由） | 1-4 / 1-6 |
| DynamoDB スロットリング | 1-5 / 2-4 |

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

---

## Phase 4: CI/CD

**`pr.yml`** — app の lint / typecheck / test / build と、terraform の fmt / validate / plan。plan 結果を PR にコメント。

**`deploy.yml`**（`main` push）— 順序が重要。

```
OIDC で assume
  ↓
docker build & push  （タグ = コミット SHA）
  ↓
terraform apply -var image_tag=<SHA>     ← Terraform がイメージタグを所有
  ↓
ECS デプロイ完了を待つ
```

**この順序である理由** — Terraform にイメージタグを所有させることで drift が出ない。
そして「**デプロイ = terraform apply**」になるため、観点1（AWS 設定起因）と観点2（コード起因）が**同じ1本のデプロイイベント**として Agent から見える。RCA デモが自然に成立する。

先に push しておかないと apply 時点でイメージが存在しないので、build&push が先。

**長期アクセスキーは一切使わない。** OIDC のみ（D-009）。

---

## Phase 5: エージェント接続

**DevOps Agent**（Terraform）— `awscc_devopsagent_agent_space` ＋ `awscc_devopsagent_association`（アカウント紐付け）。CloudWatch は同一アカウントなら追加接続不要。

**Security Agent**（Terraform）— `awscc_securityagent_agent_space`、Application、`SecurityAgentAppRole-*`、`SecurityAgentServiceRole-*`。
AWS 公式サンプル [aws-samples/sample-terraform-for-security-agent](https://github.com/aws-samples/sample-terraform-for-security-agent) を下敷きにする。

**ここだけ手作業が残る（ブラウザ操作が必須）**

1. GitHub App の認可 — DevOps Agent 側、Security Agent 側それぞれ
2. **リポジトリ選択は必ず "Only select repositories"** で `devops-agent-form` のみ
   → "All" を選ぶと既存 27 リポジトリ全部がスコープに入る（D-006）
3. ペネトレーションテストのターゲットドメイン登録（ALB の DNS 名）と **HTTP_ROUTE 検証**
   → キャンペーン型（D-011）なので期間中は 1 回で済む

**注意** — GitHub App は `OR-Sasaki` に一度しかインストールできず、**紐づけ先はこのデモアカウント1つに固定される**。

---

## Phase 6: 受け入れ確認

**故障は仕込まない**（D-005）。確認するのは「**後から仕込める状態になっているか**」。

| # | 確認項目 |
|---|---|
| 1 | フォームが動き、送信内容が DynamoDB に入り、`/admin` に出る |
| 2 | DevOps Agent のコンソールにトポロジー（ALB → ECS → DynamoDB）が出る |
| 3 | アラームが**症状ごとに分かれて**存在する |
| 4 | CloudTrail に設定変更が記録される（観点1の前提） |
| 5 | `var.fault_injection` の口が通っている（観点1の前提） |
| 6 | イメージタグ = コミット SHA がログとメトリクスに乗る（観点2の前提） |
| 7 | GitHub が DevOps Agent と Security Agent の**両方**に接続済み（観点2・3の前提） |
| 8 | ペンテストのターゲット検証が完了している（観点3の前提） |
| 9 | PR を出すと Security Agent がコードレビューコメントを付ける |

---

## コストと撤収

**コスト**

| 項目 | 金額 |
|---|---|
| インフラ | 月 $27（2週間なら約 $13） |
| DevOps Agent | $0.0083 / agent-second。無料トライアル2ヶ月 |
| Security Agent ペンテスト | **$50 / task-hour**。無料トライアルあり |

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
| Security Agent の自動修復が東京で使えない | Phase 0 で検証。ダメなら Security Agent の Agent Space だけ us-east-1 へ（D-008） |
| SCP が apply を弾く | Phase 0 で事前確認 |
| Push Protection が観点3-3 を阻む | ダミー値を使う、または Security Agent の指摘のみに絞る（D-010） |
| 脆弱なエンドポイントの公開 | キャンペーン型で期間限定（D-011）、README で警告（D-010） |
| CI が実質 Administrator 権限を持つ | 専用アカウントで爆発半径を閉じる（D-003）。OIDC の `sub` を厳密に絞る |
