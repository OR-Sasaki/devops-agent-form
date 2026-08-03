// ⚠️⚠️ 入力処理はこのファイルに集約する（D-012）。⚠️⚠️
//
// 01-fault-perspectives.md の「必要な余地」は、**バグを一箇所に閉じ込められる構造**を
// 要求している。パース・検証・保存をここから外に出すと、その要件が崩れる。
// 観点2（コード起因のバグ）と観点3（入力系の脆弱性）の仕込み先は、原則ここ1ファイルである。
//
// 後から弾を込めるときにここへ入るもの（実装しない。D-005）:
//
//   2-1 メモリリーク       モジュールスコープの配列にリクエスト毎に積む
//   2-2 未処理例外         特定入力（空メッセージ等）で null 参照
//   2-3 同期的な重い処理   validateInput の中でビジーループを回す
//   2-4 N+1               putSubmission をループで呼ぶ
//   2-5 クライアント再生成 db.ts のクライアント生成をこのファイルの関数内へ移す
//   3-2 インジェクション   Scan の FilterExpression を文字列連結で組み立てる
//
// 観点3-1（XSS）だけは表示側なので admin.tsx が担当する。

import { randomUUID } from "node:crypto";

import { putSubmission, type Submission } from "./db.js";
import { COMMIT_SHA } from "./logger.js";

/** 入力の上限。DynamoDB の項目サイズ（400KB）ではなく、フォームとして妥当な範囲で切る。 */
export const FIELD_LIMITS = {
  name: 100,
  // RFC 5321 のメールアドレス長の上限
  email: 254,
  message: 2000,
} as const;

export interface SubmissionInput {
  name: string;
  email: string;
  message: string;
}

export interface FieldError {
  field: keyof SubmissionInput;
  message: string;
}

export type SubmitResult =
  | { ok: true; submission: Submission }
  | { ok: false; errors: FieldError[]; values: SubmissionInput };

/**
 * フォームの生ボディを SubmissionInput に落とす。
 *
 * c.req.parseBody() は値として string | File を返し、同名フィールドが複数あれば
 * 配列にもなりうる。**型が来ることを前提にしない** — 想定外の型は空文字に潰す。
 */
export function extractInput(body: Record<string, unknown>): SubmissionInput {
  return {
    name: toSingleLineString(body["name"], FIELD_LIMITS.name),
    email: toSingleLineString(body["email"], FIELD_LIMITS.email),
    message: toTrimmedString(body["message"], FIELD_LIMITS.message),
  };
}

/**
 * 検証結果。空配列なら妥当。
 *
 * ⚠️ ここは「送信を弾く」ためのもので、**XSS 対策ではない。**
 *    出力側のエスケープ（hono/jsx が {} を自動エスケープする）が XSS 対策の本体であり、
 *    入力フィルタでそれを代替しようとしないこと。
 */
export function validateInput(input: SubmissionInput): FieldError[] {
  const errors: FieldError[] = [];

  if (input.name === "") {
    errors.push({ field: "name", message: "お名前を入力してください。" });
  } else if (input.name.length > FIELD_LIMITS.name) {
    errors.push({ field: "name", message: `お名前は ${FIELD_LIMITS.name} 文字以内で入力してください。` });
  }

  if (input.email === "") {
    errors.push({ field: "email", message: "メールアドレスを入力してください。" });
  } else if (input.email.length > FIELD_LIMITS.email) {
    errors.push({
      field: "email",
      message: `メールアドレスは ${FIELD_LIMITS.email} 文字以内で入力してください。`,
    });
  } else if (!isPlausibleEmail(input.email)) {
    errors.push({ field: "email", message: "メールアドレスの形式が正しくありません。" });
  }

  if (input.message === "") {
    errors.push({ field: "message", message: "お問い合わせ内容を入力してください。" });
  } else if (input.message.length > FIELD_LIMITS.message) {
    errors.push({
      field: "message",
      message: `お問い合わせ内容は ${FIELD_LIMITS.message} 文字以内で入力してください。`,
    });
  }

  return errors;
}

/** 検証を通ったときだけ id と時刻を採番する。保存する形はここでしか作らない。 */
export function buildSubmission(input: SubmissionInput): Submission {
  return {
    id: randomUUID(),
    name: input.name,
    email: input.email,
    message: input.message,
    createdAt: new Date().toISOString(),
    commitSha: COMMIT_SHA,
  };
}

/** パース → 検証 → 保存。ルーティング側（index.tsx）はこの結果を描き分けるだけにする。 */
export async function processSubmission(body: Record<string, unknown>): Promise<SubmitResult> {
  const values = extractInput(body);
  const errors = validateInput(values);

  if (errors.length > 0) {
    return { ok: false, errors, values };
  }

  const submission = buildSubmission(values);
  await putSubmission(submission);

  return { ok: true, submission };
}

// --------------------------------------------------------------------------
// 内部
// --------------------------------------------------------------------------

/** 上限の2倍で頭打ちにする。**切り詰めた値で検証すると長さ超過を見逃す**ので、余裕を持たせる。 */
function clamp(value: string, limit: number): string {
  return value.length > limit * 2 ? value.slice(0, limit * 2) : value;
}

function toTrimmedString(value: unknown, limit: number): string {
  if (typeof value !== "string") {
    return "";
  }
  return clamp(value.trim(), limit);
}

/** 1行フィールド用。改行を含む値はヘッダ注入等の温床になるので空白に潰す。 */
function toSingleLineString(value: unknown, limit: number): string {
  return toTrimmedString(value, limit).replace(/[\r\n\t]+/g, " ");
}

/**
 * メールアドレスの形式チェック。
 *
 * RFC 5322 の完全な検証はしない（現実の実装はどれもしていない）。
 * 「@ を1つ挟んで両側に空白の無い文字があり、ドメインにドットがある」程度で十分。
 */
function isPlausibleEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/.test(value);
}
