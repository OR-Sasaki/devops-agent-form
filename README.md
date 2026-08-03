# ⚠️ このリポジトリを本番で使わないこと / DO NOT USE IN PRODUCTION

> **これは AWS DevOps Agent と AWS Security Agent を検証するためのサンドボックスです。**
>
> **意図的な脆弱性と意図的な障害を仕込むことを目的に設計されています。**
> エージェントに何を検出させるかを実験するため、脆弱なコードや壊れたインフラ設定が
> **任意のコミット時点で入っている可能性があります**（デモの前後で入れて消します）。
>
> - **本番環境で使わないでください**
> - **一部でも他プロジェクトへコピーしないでください**
> - ここにある IAM ポリシー・ネットワーク構成・入力処理は**参考にしてはいけません**
> - 本物のシークレットは一切含みません。それらしく見える値はすべてダミーです

> **This is a deliberately vulnerable sandbox for evaluating AWS DevOps Agent and AWS Security Agent.**
> Intentional security flaws and misconfigurations are planted here on purpose and may be
> present at any given commit. **Do not use it in production. Do not copy any part of it.**
> It contains no real secrets — anything that looks like one is a dummy value.

---

## これは何か

AWS の2つのフロンティアエージェントに「実際に壊れたシステム」を見せて、
どこまで自律的に調査・指摘できるかを測るための検証環境です。

| | 見たいこと |
|---|---|
| **DevOps Agent** | アラームを起点に根本原因まで辿れるか。CI/CD の失敗を調査できるか |
| **AWS Security Agent** | PR の時点で脆弱性を指摘できるか。稼働中のエンドポイントにペネトレーションテストで到達できるか |

題材は**問い合わせフォーム**です。ただしフォーム自体は目的ではなく、
**「壊れたときにエージェントが辿れる痕跡を残す器」**として存在しています。
この区別は [CONTEXT.md](./CONTEXT.md) に用語として定義してあります。

## 現在の状態

**構築の途中です。** `terraform/bootstrap/`（state バケット・OIDC・ECR・CloudTrail・予算）だけが作られており、
`terraform/main/`（ネットワーク・ALB・ECS・DynamoDB）と `app/` はまだ空です。
どこまで進んだかは [docs/plan/02-implementation-plan.md](./docs/plan/02-implementation-plan.md) の各 Phase の進捗表を見てください。

**この時点でのコードに、意図的な脆弱性はまだ入っていません。** 冒頭の警告は、
このリポジトリが**これから脆弱性を入れる場所である**ことに対するものです。

## 構成

```
ALB → ECS Fargate (Hono / TypeScript) → DynamoDB
                ↑
      GitHub Actions が OIDC で assume して terraform apply
```

- リージョンは `ap-northeast-1` 単一
- インフラもアプリも `main` へのマージで CI から apply される（完全 GitOps）
- CI に長期アクセスキーは置かない。GitHub OIDC のみ

## ディレクトリ

| パス | 中身 |
|---|---|
| [CONTEXT.md](./CONTEXT.md) | 用語集。用語が揺れたらコードより先にここを直す |
| [docs/plan/00-decisions.md](./docs/plan/00-decisions.md) | 決定ログ。なぜそう決めたかと、確認済みの外部事実 |
| [docs/plan/01-fault-perspectives.md](./docs/plan/01-fault-perspectives.md) | 故障観点カタログ（何を仕込みうるかの一覧） |
| [docs/plan/02-implementation-plan.md](./docs/plan/02-implementation-plan.md) | Phase 0〜6 の実装計画 |
| `terraform/bootstrap/` | ローカルから1回だけ apply する層。state バケット・OIDC・ECR・CloudTrail・予算 |
| `terraform/main/` | CI が apply する層。state は S3 |
| `.github/workflows/` | CI/CD |
| `app/` | フォームアプリ（Hono + TypeScript） |

`terraform/bootstrap/` の state は**ローカルにしか存在しません**（`.gitignore` で除外）。

## 稼働期間

検証期間が終わったら `terraform destroy` します。
**脆弱なエンドポイントを常時公開しないための措置**でもあります。

## ライセンス

**ありません。** 再利用を想定していないためです。上の警告を読んでください。
