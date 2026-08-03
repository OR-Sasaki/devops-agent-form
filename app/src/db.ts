// DynamoDB アクセス。テーブルの形は terraform/main/dynamodb.tf が決めている。
//
//   テーブル名   devops-agent-form-submissions（TABLE_NAME で注入される）
//   hash_key     id (S)
//   GSI          無い
//
// タスクロールに付いているのは GetItem / Query / Scan / PutItem で、
// **リソースはテーブル ARN のみ**（index ARN を含まない）。ecs.tf を参照。

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand, ScanCommand } from "@aws-sdk/lib-dynamodb";

export interface Submission {
  id: string;
  name: string;
  email: string;
  message: string;
  createdAt: string;
  /** この行を書いたデプロイのコミット SHA。観点2 で「いつ入ったデータか」を辿るために持つ。 */
  commitSha: string;
}

const TABLE_NAME = process.env.TABLE_NAME ?? "";

// ⚠️ SDK クライアントはモジュールスコープで1つだけ作る。**これが健全な状態である。**
//    観点2-5（毎リクエストで SDK クライアントを生成 → 接続枯渇）は、
//    この2行を関数の内側へ移すことで仕込む。
//
//    リージョンは AWS_REGION 環境変数から解決される（ecs.tf が注入する）。
const client = new DynamoDBClient({});
const documentClient = DynamoDBDocumentClient.from(client, {
  marshallOptions: { removeUndefinedValues: true },
});

export async function putSubmission(item: Submission): Promise<void> {
  await documentClient.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));
}

/**
 * 送信一覧を新しい順に返す。
 *
 * ⚠️ Query ではなく Scan を使う理由 — テーブルに GSI が無く（dynamodb.tf）、
 *    タスクロールの権限もテーブル ARN のみで index ARN を含まない（ecs.tf）。
 *    デモ規模（数十件）なので Scan で足りる。
 *
 * ⚠️ FilterExpression は使わない。式を文字列連結で組み立てると観点3-2
 *    （DynamoDB の式インジェクション）が成立する。絞り込みが要るようになったら、
 *    必ず ExpressionAttributeNames / ExpressionAttributeValues のプレースホルダに値を渡すこと。
 */
export async function listSubmissions(limit = 50): Promise<Submission[]> {
  const result = await documentClient.send(
    new ScanCommand({ TableName: TABLE_NAME, Limit: limit }),
  );

  const items = (result.Items ?? []) as Submission[];
  return items.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
}
