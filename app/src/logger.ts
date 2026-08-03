// 構造化 JSON ログ。**COMMIT_SHA を必ず載せる。**
//
// 01-fault-perspectives.md 観点2 は、相関の経路を
// 「アラーム → ログ（SHA）→ ECS タスク定義（イメージタグ）→ コミット」と決めている。
// SHA が乗っていないと Agent がログからコードへ降りてこられず、観点2 のデモがそこで止まる。
// SHA が残る3箇所のうち、**この1行がアプリの担当**である。
//
// awslogs ドライバは stdout / stderr をそのまま CloudWatch Logs へ流す（observability.tf）。
// 1行1 JSON にしておくと Logs Insights がフィールドとして解析でき、
// `fields @timestamp, commitSha, requestId | filter level = "error"` が書ける。

/** ECS タスク定義が注入する（ecs.tf の container_definitions）。値はコミット SHA。 */
export const COMMIT_SHA = process.env.COMMIT_SHA ?? "unknown";

type Level = "info" | "warn" | "error";

export type LogFields = Record<string, unknown>;

/** Error はそのままだと JSON.stringify で {} になるので、明示的に展開する。 */
function serializeError(value: unknown): unknown {
  if (value instanceof Error) {
    return { name: value.name, message: value.message, stack: value.stack };
  }
  return value;
}

function emit(level: Level, message: string, fields: LogFields = {}): void {
  const entry: Record<string, unknown> = {
    timestamp: new Date().toISOString(),
    level,
    message,
    commitSha: COMMIT_SHA,
  };

  for (const [key, value] of Object.entries(fields)) {
    entry[key] = key === "error" || key === "cause" ? serializeError(value) : value;
  }

  // ログ出力そのものが例外を投げてリクエストを巻き込むのが最悪なので、ここで閉じる。
  // 循環参照や BigInt が混ざると JSON.stringify は throw する。
  let line: string;
  try {
    line = JSON.stringify(entry);
  } catch {
    line = JSON.stringify({
      timestamp: entry["timestamp"],
      level: "error",
      message: "log serialization failed",
      commitSha: COMMIT_SHA,
      originalMessage: message,
    });
  }

  if (level === "error") {
    process.stderr.write(`${line}\n`);
  } else {
    process.stdout.write(`${line}\n`);
  }
}

export const logger = {
  info: (message: string, fields?: LogFields): void => emit("info", message, fields),
  warn: (message: string, fields?: LogFields): void => emit("warn", message, fields),
  error: (message: string, fields?: LogFields): void => emit("error", message, fields),
};
