# Zone モジュール

一つの Cloudflare Zone と、その DNS レコード、ゾーン設定、利用者が管理するルールセットを管理します。state と import は呼び出し元の root が管理します。

| 入力 | 型 | 内容 |
| --- | --- | --- |
| `account_id` | `string` | 非公開の Account ID |
| `zone` | `object` | 非公開の Zone ID、名前、種類、停止状態 |
| `dns_records` | `map(object)` | この Zone に属する既存 DNS レコード |
| `settings` | `map(object)` | 設定 ID と JSON 文字列の値 |
| `rulesets` | `map(object)` | 既存ルールセットの属性と JSON 文字列のルール配列 |

各マップのキーは、実際のドメインや ID を含まない安定したローカル名にしてください。詳細な型と検証条件は `variables.tf` にあります。

`settings.value_json` は JSON として有効かつ非 null の値を指定します。`rulesets.rules_json` は JSON 配列を指定します。DNS の `data.flags` は Provider の動的型に合わせています。

使用例は `stacks/zone`、値を含まない設定例は `examples/zone.tfvars.json.example` を参照してください。
