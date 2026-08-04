// ルーティングとサーバ起動。**入力処理はここに書かない**（submit.ts に集約する。D-012）。
//
// terraform/main/ が決めているアプリの契約:
//
//   ポート            3000（PORT で注入。var.container_port）
//   ヘルスチェック     GET /healthz が 200（alb.tf。15 秒間隔 / タイムアウト 5 秒 / 閾値 2）
//   環境変数          COMMIT_SHA / TABLE_NAME / AWS_REGION / PORT / NODE_ENV
//                    ＋ ADMIN_USERNAME / ADMIN_PASSWORD（D-035）
//   ログ              stdout / stderr → awslogs → /ecs/devops-agent-form

import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { secureHeaders } from "hono/secure-headers";
import { randomUUID } from "node:crypto";

import { AdminPage, adminAuth } from "./admin.js";
import { listSubmissions } from "./db.js";
import { COMMIT_SHA, logger } from "./logger.js";
import {
  FIELD_LIMITS,
  processSubmission,
  type FieldError,
  type SubmissionInput,
} from "./submit.js";

type Env = { Variables: { requestId: string } };

const app = new Hono<Env>();

// --------------------------------------------------------------------------
// ミドルウェア
// --------------------------------------------------------------------------

// ⚠️ セキュリティヘッダはベースラインで付ける（D-035）。
//    観点3-7「セキュリティヘッダ欠如」は**故障として**カタログに載っているので、
//    最初から欠いた状態で置くと、それ自体が故障を先に仕込んだことになる。
//
// このアプリはサーバーレンダリングのみでクライアント JS を1行も使わない。
// したがって default-src 'none' まで締められる。スタイルは /style.css で配るので
// style-src は 'self' で足り、'unsafe-inline' が要らない。
app.use(
  "*",
  secureHeaders({
    contentSecurityPolicy: {
      defaultSrc: ["'none'"],
      styleSrc: ["'self'"],
      formAction: ["'self'"],
      baseUri: ["'none'"],
      frameAncestors: ["'none'"],
    },
    // ⚠️ HSTS は出さない。ALB に HTTPS リスナーが無く（D-007）、
    //    守れない約束をヘッダで宣言することになるため。
    //    ドメインと ACM 証明書を付けたら、ここを有効にする。
    strictTransportSecurity: false,
    xFrameOptions: "DENY",
    referrerPolicy: "no-referrer",
  }),
);

// ⚠️ CORS ミドルウェアは**入れない**。
//    同一オリジンのフォームしか無いので不要であり、観点3-5（過剰な CORS 設定）は
//    ここに hono/cors を足して origin: "*" にすることで仕込む。

app.use("*", async (c, next) => {
  const requestId = randomUUID();
  c.set("requestId", requestId);
  const startedAt = Date.now();

  await next();

  // ALB のヘルスチェックは 15 秒 × 2 ターゲットで叩いてくる。
  // 全部記録すると CloudWatch Logs が健全時のノイズで埋まり、保存料も増える。
  // 死活は ALB のメトリクス側で見えるので、ここでは落とす。
  if (c.req.path === "/healthz") {
    return;
  }

  logger.info("request", {
    requestId,
    // ALB が付けるトレース ID。ALB のログ・メトリクスと突き合わせる手がかりになる。
    traceId: c.req.header("x-amzn-trace-id"),
    method: c.req.method,
    path: c.req.path,
    status: c.res.status,
    durationMs: Date.now() - startedAt,
    clientIp: clientIpOf(c.req.header("x-forwarded-for")),
  });
});

// --------------------------------------------------------------------------
// ルート
// --------------------------------------------------------------------------

app.get("/", (c) =>
  c.html(
    <Layout title="お問い合わせ">
      <FormPage />
    </Layout>,
  ),
);

app.post("/submit", async (c) => {
  const body = await c.req.parseBody();
  const result = await processSubmission(body);

  if (!result.ok) {
    logger.warn("submission rejected", {
      requestId: c.get("requestId"),
      fields: result.errors.map((error) => error.field),
    });
    return c.html(
      <Layout title="お問い合わせ">
        <FormPage errors={result.errors} values={result.values} />
      </Layout>,
      400,
    );
  }

  logger.info("submission stored", {
    requestId: c.get("requestId"),
    submissionId: result.submission.id,
    // 名前そのものは載せない（個人情報である）。長さの区分だけ残す。submit.ts を参照。
    nameLengthBucket: result.nameLengthBucket,
  });

  return c.html(
    <Layout title="送信しました">
      <h1>送信しました</h1>
      <p>お問い合わせを受け付けました。</p>
      <p class="meta">
        受付 ID: <code>{result.submission.id}</code>
      </p>
      <p>
        <a href="/">フォームへ戻る</a>
      </p>
    </Layout>,
  );
});

app.get("/admin", adminAuth, async (c) => {
  const submissions = await listSubmissions();
  return c.html(
    <Layout title="送信一覧">
      <AdminPage submissions={submissions} />
    </Layout>,
  );
});

// ALB のターゲットヘルスチェック（alb.tf）。matcher は "200"。
// commitSha を返しておくと、どのデプロイが応答しているかを curl 1発で確認できる。
app.get("/healthz", (c) => c.json({ status: "ok", commitSha: COMMIT_SHA }));

app.get("/style.css", (c) => {
  c.header("Content-Type", "text/css; charset=utf-8");
  c.header("Cache-Control", "public, max-age=3600");
  return c.body(STYLESHEET);
});

app.notFound((c) =>
  c.html(
    <Layout title="見つかりません">
      <h1>404</h1>
      <p>ページが見つかりません。</p>
      <p>
        <a href="/">フォームへ戻る</a>
      </p>
    </Layout>,
    404,
  ),
);

app.onError((err, c) => {
  // ⚠️⚠️ HTTPException を 500 に潰さないこと。⚠️⚠️
  //
  // hono/basic-auth は認証失敗時に 401 応答を持った HTTPException を throw する。
  // この分岐が無いと **Basic 認証の失敗が 5xx になり、ALB 5xx アラームが鳴る**。
  // 観点1-1 / 2-2 用のアラームが「誰かが /admin のパスワードを間違えた」で鳴るようになり、
  // アラームと症状の対応が壊れる。ローカルの疎通確認で実際に踏んだ（500 が返っていた）。
  if (err instanceof HTTPException) {
    logger.warn("http exception", {
      requestId: c.get("requestId"),
      method: c.req.method,
      path: c.req.path,
      status: err.status,
    });
    return err.getResponse();
  }

  // ⚠️ 観点2-2（特定入力での未処理例外）が 5xx として現れるのはここ。
  //    ALB 5xx アラーム（observability.tf）が鳴り、この行が Agent の降り口になる。
  logger.error("unhandled error", {
    requestId: c.get("requestId"),
    method: c.req.method,
    path: c.req.path,
    error: err,
  });

  // 例外の内容は返さない。スタックトレースを画面に出すのは情報漏洩になる。
  return c.html(
    <Layout title="エラー">
      <h1>エラーが発生しました</h1>
      <p>時間をおいて再度お試しください。</p>
    </Layout>,
    500,
  );
});

// --------------------------------------------------------------------------
// ビュー
// --------------------------------------------------------------------------

function Layout({ title, children }: { title: string; children?: unknown }) {
  return (
    <html lang="ja">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{title} | DevOps Agent Sandbox</title>
        <link rel="stylesheet" href="/style.css" />
      </head>
      <body>
        <main>{children}</main>
        <footer class="meta">
          <p>
            AWS DevOps Agent / Security Agent の検証用サンドボックスです。本番利用禁止。 build{" "}
            <code>{COMMIT_SHA.slice(0, 7)}</code>
          </p>
        </footer>
      </body>
    </html>
  );
}

function FormPage({
  errors = [],
  values,
}: {
  errors?: FieldError[];
  values?: SubmissionInput;
}) {
  const messageFor = (field: keyof SubmissionInput): string | undefined =>
    errors.find((error) => error.field === field)?.message;

  return (
    <>
      <h1>お問い合わせ</h1>

      {errors.length > 0 && (
        <p class="error" role="alert">
          入力内容を確認してください。
        </p>
      )}

      <form method="post" action="/submit">
        <label for="name">お名前</label>
        <input
          id="name"
          name="name"
          type="text"
          maxlength={FIELD_LIMITS.name}
          value={values?.name ?? ""}
          required
        />
        <FieldMessage message={messageFor("name")} />

        <label for="email">メールアドレス</label>
        <input
          id="email"
          name="email"
          type="email"
          maxlength={FIELD_LIMITS.email}
          value={values?.email ?? ""}
          required
        />
        <FieldMessage message={messageFor("email")} />

        <label for="message">お問い合わせ内容</label>
        <textarea id="message" name="message" rows={8} maxlength={FIELD_LIMITS.message} required>
          {values?.message ?? ""}
        </textarea>
        <FieldMessage message={messageFor("message")} />

        <button type="submit">送信する</button>
      </form>
    </>
  );
}

function FieldMessage({ message }: { message?: string | undefined }) {
  if (message === undefined) {
    return <></>;
  }
  return <p class="error">{message}</p>;
}

// クライアント JS を持たないので、CSS も1ファイルで足りる。
// インライン <style> にしないのは、CSP の style-src から 'unsafe-inline' を外すため。
const STYLESHEET = `:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body {
  margin: 0 auto; padding: 2rem 1rem; max-width: 56rem; line-height: 1.7;
  font-family: system-ui, -apple-system, "Hiragino Sans", "Noto Sans JP", sans-serif;
}
h1 { font-size: 1.5rem; margin-top: 0; }
label { display: block; margin-top: 1rem; font-weight: 600; }
input, textarea {
  width: 100%; padding: 0.5rem; font: inherit;
  border: 1px solid currentColor; border-radius: 4px; background: transparent; color: inherit;
}
button {
  margin-top: 1.5rem; padding: 0.6rem 1.4rem; font: inherit;
  border: 1px solid currentColor; border-radius: 4px; background: transparent; color: inherit;
  cursor: pointer;
}
table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
th, td { border: 1px solid currentColor; padding: 0.4rem 0.6rem; text-align: left; vertical-align: top; }
th { font-size: 0.85rem; }
td.nowrap { white-space: nowrap; }
td.message { white-space: pre-wrap; word-break: break-word; }
p.error { color: #b00020; font-weight: 600; margin: 0.25rem 0 0; }
.meta { font-size: 0.85rem; opacity: 0.75; }
footer { margin-top: 3rem; border-top: 1px solid currentColor; }
`;

// --------------------------------------------------------------------------
// 起動
// --------------------------------------------------------------------------

/**
 * ALB が付ける X-Forwarded-For から接続元を取る。
 *
 * ALB は**受け取ったヘッダの末尾に自分が観測した接続元を追記する**ので、
 * 利用者が偽の XFF を送ってきても**最後の要素は信頼できる**。先頭を取ってはいけない。
 */
function clientIpOf(header: string | undefined): string | undefined {
  if (header === undefined) {
    return undefined;
  }
  const parts = header.split(",");
  return parts[parts.length - 1]?.trim();
}

const port = Number(process.env.PORT ?? 3000);

const server = serve({ fetch: app.fetch, port, hostname: "0.0.0.0" }, (info) => {
  logger.info("server started", {
    port: info.port,
    nodeEnv: process.env.NODE_ENV ?? "development",
    tableName: process.env.TABLE_NAME ?? "",
    region: process.env.AWS_REGION ?? "",
    adminAuthConfigured: (process.env.ADMIN_PASSWORD ?? "") !== "",
  });
});

// ECS はタスクを止めるとき SIGTERM を送り、30 秒待ってから SIGKILL する。
// 受けて閉じておくと停止が速く、ログも「なぜ止まったか」が分かる形で残る。
process.on("SIGTERM", () => {
  logger.info("SIGTERM received; shutting down");
  server.close(() => process.exit(0));
});
