# 観点1（AWS 設定起因）の切り替え口。**Phase 2 では使わない**（D-005）。
#
# D-005 が要求しているのは「健全な設定と劣化した設定を変数ひとつで切り替えられる粒度」。
# それをどう実現するかは決まっていなかったので、ここで決めた（D-026）。
#
#   このファイルは var.fault_injection から**効果値**を1箇所で算出するだけにする。
#   リソースそのものは分岐させず、各 .tf が local.fault.* を読む。
#
# こうする理由 ——
#
#   1. **何が壊れるかがここだけを見れば分かる。** 故障ごとに .tf をまたいで差分を追う必要が無い。
#      これは Agent の実力を測る側（人間）にとっての要件で、デモ中に「今どこを壊しているか」を
#      即答できないと、Agent の答え合わせができない
#   2. **count による分岐を最小にできる。** count でリソースを生やし分けると、切り替えのたびに
#      破棄と再作成が起きる。ALB を作り直すと DNS 名が変わり、ペンテストのターゲット検証が
#      失効する（D-011 がキャンペーン型を選んだのと同じ理由）
#   3. **健全な状態が既定であることが1行で読める。** 各 local が "none" のときに何になるかを
#      三項演算子の else 側に置いてあるので、既定値の確認に他ファイルを開かなくてよい
#
# ⚠️ 故障を足すときは、必ず対応する CloudWatch アラームが鳴ることを確認すること。
#    鳴らない故障は「インシデント面」の定義（CONTEXT.md）を満たさず、デモとして成立しない。

locals {
  fault = var.fault_injection

  # 1-1 タスクロールから dynamodb:PutItem を剥がす
  #     → フォーム送信が全件 5xx。参照は正常なので「書き込み系だけが落ちている」が症状になる。
  #     アプリが書き込みに使うのは PutItem だけなので、剥がすのも PutItem だけでよい。
  fault_deny_dynamodb_write = local.fault == "iam_denied"

  # 1-2 ALB のヘルスチェックパスを存在しないパスに変更
  #     → ターゲット全台 unhealthy → 503。アプリ自体は生きている。
  health_check_path = local.fault == "bad_healthcheck" ? "/__no_such_path__" : "/healthz"

  # 1-3 ALB → タスクの SG ingress を閉じる
  #     → ALB からタスクへ到達不可。
  fault_close_ecs_ingress = local.fault == "closed_sg"

  # 1-4 コンテナのメモリハードリミットを極端に小さくする
  #     → OOM でタスクが再起動ループ。
  #     ⚠️ タスク単位のメモリ（var.task_memory）ではなくコンテナ単位のハードリミットを下げる。
  #        Fargate のタスクメモリは離散値（0.25 vCPU なら 512/1024/2048）しか受け付けず、
  #        「極端に小さい値」を表現できないため。コンテナ側なら任意の値を置ける。
  container_memory_hard_limit = local.fault == "low_memory" ? 64 : var.task_memory

  # 1-5 DynamoDB をオンデマンド → 低容量プロビジョンドへ変更
  #     → 書き込みスロットリング、レイテンシ悪化。
  fault_dynamodb_provisioned = local.fault == "dynamodb_throttle"

  # 1-6 public subnet のデフォルトルートを落とす
  #     → ECR からイメージを pull できずタスク起動失敗。
  #     ⚠️ これは assign_public_ip の指定漏れと**症状が同一**（Phase 2 の必須要件を参照）。
  #        仕込んでいないのにこの症状が出たら、まず ecs.tf の assign_public_ip を疑うこと。
  fault_break_default_route = local.fault == "broken_route"
}
