# Account Security モジュール

複数の Zone から参照する Account 単位のセキュリティ資源を管理します。state と import は呼び出し元の root が管理します。

| 入力 | 型 | 内容 |
| --- | --- | --- |
| `account_id` | `string` | 非公開の Account ID |
| `ip_lists` | `map(object)` | WAF から参照する IP リスト。Free プランは 1 リストまで |
| `turnstile_widgets` | `map(object)` | フォームやログインに使う Turnstile ウィジェット。Free プランは 20 個まで |

## IP リスト

Free プランで作成できる Custom List は IP リストだけです。`name` は WAF の式から `ip.src in $allowed_ips` のように参照します。ASN やホスト名のリスト、複数の IP リストは有料プランの機能です。

`items` には IP アドレスまたは CIDR を指定します。既存リストを管理する場合は `import_id` にリスト ID を指定します。`items` を省略すると既存項目を変更せずに import できます。明示的に空配列を指定した場合だけ、既存項目をすべて削除します。`import_id` を省略した場合は新規作成します。

## Turnstile

`domains` にはウィジェットを設置するホスト名を指定します。`mode` は `managed`、`non-interactive`、`invisible` のいずれかです。既存ウィジェットを管理する場合は `import_id` に sitekey を指定します。

Free 向けのモジュールでは、Enterprise 専用の `bot_fight_mode`、`ephemeral_id`、`offlabel` は公開していません。Turnstile の sitekey は公開値ですが、secret は Terraform state に保存されます。state は非公開 R2 で管理してください。

## Free プランの注意

- IP リストは 1 Account あたり 1 つ
- Turnstile は 1 Account あたり 20 ウィジェット
- Turnstile の siteverify は無料枠の範囲で利用

上限はプラン変更や Cloudflare 側の仕様変更で変わる可能性があります。
