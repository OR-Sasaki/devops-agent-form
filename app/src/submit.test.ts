// submit.ts の入力処理のテスト。Node 22 の組み込みテストランナー（node:test）を使う。
// テストフレームワークを足さないのは、依存が増えるほどイメージと CI が重くなるため。
//
// ⚠️ 動的 import にしている理由 — submit.ts は db.ts を読み、db.ts は
//    モジュールスコープで DynamoDB クライアントを生成する（そこが健全な形である）。
//    静的 import は巻き上げられて process.env の設定より先に走るので、
//    環境変数を置いてから import する必要がある。

import assert from "node:assert/strict";
import test from "node:test";

process.env["AWS_REGION"] ??= "ap-northeast-1";
process.env["TABLE_NAME"] ??= "devops-agent-form-submissions-test";
process.env["COMMIT_SHA"] ??= "0000000000000000000000000000000000000000";

const { extractInput, validateInput, buildSubmission, FIELD_LIMITS } = await import("./submit.js");

const valid = { name: "山田 太郎", email: "taro@example.com", message: "こんにちは" };

test("extractInput は前後の空白を落とす", () => {
  const input = extractInput({ name: "  太郎  ", email: " taro@example.com ", message: " 本文 " });
  assert.deepEqual(input, { name: "太郎", email: "taro@example.com", message: "本文" });
});

test("extractInput は文字列以外の値を空文字に潰す", () => {
  // parseBody() は File や配列を返しうる。型が来ることを前提にしない。
  const input = extractInput({ name: ["a", "b"], email: 42, message: undefined });
  assert.deepEqual(input, { name: "", email: "", message: "" });
});

test("extractInput は1行フィールドの改行を空白に潰す", () => {
  const input = extractInput({ name: "太郎\r\n偽ヘッダ", email: "a@example.com", message: "x" });
  assert.equal(input.name, "太郎 偽ヘッダ");
});

test("extractInput は本文の改行を保つ", () => {
  const input = extractInput({ name: "太郎", email: "a@example.com", message: "1行目\n2行目" });
  assert.equal(input.message, "1行目\n2行目");
});

test("validateInput は妥当な入力を通す", () => {
  assert.deepEqual(validateInput(valid), []);
});

test("validateInput は空欄を3つとも報告する", () => {
  const errors = validateInput({ name: "", email: "", message: "" });
  assert.deepEqual(
    errors.map((error) => error.field),
    ["name", "email", "message"],
  );
});

test("validateInput はメールアドレスの形式を見る", () => {
  for (const email of ["taro", "taro@", "@example.com", "taro@example", "a b@example.com"]) {
    const errors = validateInput({ ...valid, email });
    assert.equal(errors.length, 1, `${email} が通ってしまった`);
    assert.equal(errors[0]?.field, "email");
  }
});

test("validateInput は上限超過を報告する", () => {
  const errors = validateInput({ ...valid, message: "あ".repeat(FIELD_LIMITS.message + 1) });
  assert.deepEqual(
    errors.map((error) => error.field),
    ["message"],
  );
});

test("上限ちょうどは通す", () => {
  assert.deepEqual(validateInput({ ...valid, message: "あ".repeat(FIELD_LIMITS.message) }), []);
});

test("extractInput の切り詰めは長さ超過を隠さない", () => {
  // 上限で切ってしまうと validateInput が「上限ちょうど」と見て通してしまう。
  const input = extractInput({ ...valid, message: "あ".repeat(FIELD_LIMITS.message + 10) });
  assert.equal(validateInput(input).length, 1);
});

test("buildSubmission は id・createdAt・commitSha を採番する", () => {
  const submission = buildSubmission(valid);

  assert.match(
    submission.id,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
  assert.equal(submission.createdAt, new Date(submission.createdAt).toISOString());
  assert.equal(submission.commitSha, process.env["COMMIT_SHA"]);
  assert.equal(submission.name, valid.name);
});

test("buildSubmission は入力をエスケープしない（出力側の責務である）", () => {
  // 入力フィルタで XSS を防ごうとしない、という設計判断をテストで固定しておく。
  // エスケープは hono/jsx が描画時に行う（admin.tsx）。
  const payload = '<script>alert(1)</script>';
  assert.equal(buildSubmission({ ...valid, message: payload }).message, payload);
});
