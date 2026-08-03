// 送信一覧（GET /admin）。**観点3-1（XSS）と観点3-4（認証なしの管理エンドポイント）の
// 仕込み先はこのファイルである**（D-012）。
//
// ⚠️ ベースラインには認証を付ける（D-035）。
//    01-fault-perspectives.md の観点3-4 は「認証・認可のない管理エンドポイント」を
//    **故障として**挙げている。最初から認証なしで置くと、それ自体が観点3-4 を
//    先に仕込んだことになり、Phase 6 項目10（この時点のコードに脆弱性は無い、という前提）が崩れる。
//    観点3-4 を仕込むときは、このファイルの adminAuth を素通しにする。

import { basicAuth } from "hono/basic-auth";
import type { MiddlewareHandler } from "hono";

import type { Submission } from "./db.js";
import { logger } from "./logger.js";

// ADMIN_USERNAME は平文の環境変数、ADMIN_PASSWORD は SSM Parameter Store の
// SecureString から ECS の secrets 機構で注入される（ecs.tf / D-035）。
// **リポジトリにもタスク定義にも平文で置かない。** 置くと観点3-3 を先に仕込むことになる。
const ADMIN_USERNAME = process.env.ADMIN_USERNAME ?? "";
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? "";

/**
 * /admin の Basic 認証。
 *
 * ⚠️ 認証情報が注入されていないときは **503 で閉じる**（fail closed）。
 *    素通しにすると、SSM の設定ミスが「管理画面が誰でも見られる」に化ける。
 *    アプリ全体を起動失敗にしないのは、フォーム側まで巻き添えにしないため。
 */
export const adminAuth: MiddlewareHandler =
  ADMIN_USERNAME !== "" && ADMIN_PASSWORD !== ""
    ? basicAuth({ username: ADMIN_USERNAME, password: ADMIN_PASSWORD })
    : async (c) => {
        logger.error("admin credentials are not configured; refusing access", {
          path: c.req.path,
        });
        return c.text("Admin console is unavailable.", 503);
      };

/**
 * 一覧の中身。ページ全体の枠は index.tsx の Layout が持つ。
 *
 * ⚠️ 観点3-1（XSS）の仕込み先。
 *    hono/jsx は {} に埋めた値を**自動でエスケープする**ので、この形のままなら安全である。
 *    3-1 を仕込むときは raw() / dangerouslySetInnerHTML を持ち込む。
 */
export function AdminPage({ submissions }: { submissions: Submission[] }) {
  return (
    <>
      <h1>送信一覧</h1>
      <p class="meta">{submissions.length} 件（新しい順・最大 50 件）</p>

      {submissions.length === 0 ? (
        <p>まだ送信がありません。</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>受信日時 (UTC)</th>
              <th>お名前</th>
              <th>メールアドレス</th>
              <th>お問い合わせ内容</th>
              <th>デプロイ</th>
            </tr>
          </thead>
          <tbody>
            {submissions.map((submission) => (
              <tr>
                <td class="nowrap">{submission.createdAt}</td>
                <td>{submission.name}</td>
                <td>{submission.email}</td>
                <td class="message">{submission.message}</td>
                {/* この行を書いたデプロイの SHA。アラーム → ログ → コミットの相関を
                    画面上でも辿れるようにしておく（観点2） */}
                <td class="nowrap">
                  <code>{submission.commitSha.slice(0, 7)}</code>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <p>
        <a href="/">フォームへ戻る</a>
      </p>
    </>
  );
}
