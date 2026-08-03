# マルチステージ。実行イメージに TypeScript のツールチェーンと devDependencies を残さない。
#
# ⚠️ アーキテクチャ — ビルドするのは GitHub Actions の ubuntu-latest（x86_64）である。
#    terraform/main/ecs.tf が runtime_platform.cpu_architecture = "X86_64" を明示しているので、
#    **手元の Mac（arm64）で焼いて push するとタスクが exec format error で起動しない。**
#    ローカルで焼くときは docker build --platform linux/amd64 を必ず付けること。
#
# ⚠️ HEALTHCHECK は置かない（D-027）。node:22-slim に curl / wget が無いことに加え、
#    ECS がタスクを勝手に差し替えると、仕込んだ故障が自己回復して観測できなくなる。
#    死活監視は ALB のターゲットヘルスチェック（GET /healthz）が担う（alb.tf）。

FROM node:22-slim AS build

WORKDIR /app

# 依存の解決だけを先に済ませてレイヤーキャッシュを効かせる。
COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ビルド後に devDependencies を落として、そのまま実行イメージへ持っていく。
# 別ステージで npm ci --omit=dev をやり直すより速い。
RUN npm prune --omit=dev

FROM node:22-slim AS runtime

ENV NODE_ENV=production
WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./

# node:22-slim には uid 1000 の node ユーザーが居る。root で走らせない。
USER node

# ドキュメント目的。実際のポートは PORT 環境変数（ecs.tf が 3000 を注入）で決まる。
EXPOSE 3000

CMD ["node", "dist/index.js"]
