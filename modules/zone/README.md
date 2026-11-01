# Zone モジュール

一つの Cloudflare Zone と、その DNS レコード、ゾーン設定、WAF・Bot・TLS に関わるセキュリティ設定を管理します。state と import は呼び出し元の root が管理します。

## 入力

| 入力 | 型 | 内容 |
| --- | --- | --- |
| `account_id` | `string` | 非公開の Account ID |
| `zone` | `object` | 非公開の Zone ID、名前、種類、停止状態 |
| `dns_records` | `map(object)` | この Zone に属する既存 DNS レコード |
| `settings` | `map(object)` | 設定 ID と JSON 文字列の値 |
| `rulesets` | `map(object)` | 利用者が所有する Zone ルールセット。`id` を省略すると新規作成、指定すると import |
| `managed_rulesets` | `map(object)` | Free Managed Ruleset や L7 DDoS など、Cloudflare 管理ルールセットの上書き。既存 `id` が必須 |
| `bot_management` | `object` | Bot Fight Mode、AI Bot 遮断、AI Labyrinth、管理 robots.txt |
| `url_normalization` | `object` | WAF 評価前の URL 正規化 |
| `dnssec` | `object` | DNSSEC の有効化状態 |
| `managed_transforms` | `object` | セキュリティヘッダーや漏洩資格情報ヘッダーの Managed Transform |
| `leaked_credential_check` | `bool` | 漏洩資格情報チェックの有効化 |
| `authenticated_origin_pulls` | `bool` | Zone 単位の Authenticated Origin Pulls |
| `access_rules` | `map(object)` | IP・ASN・国単位のアクセスルール |
| `user_agent_blocking_rules` | `map(object)` | User-Agent 単位のブロックルール |

各マップのキーは、実際のドメインや ID を含まない安定したローカル名にしてください。詳細な型と検証条件は `variables.tf` にあります。

## セキュリティ設定

`bot_management`、`url_normalization`、`dnssec`、`managed_transforms`、`leaked_credential_check`、`authenticated_origin_pulls` は singleton 設定です。値を指定した場合だけリソースを作成し、root の `imports.tf` が既存設定を import します。設定を管理対象にしない場合は `null` のままにします。

`settings.value_json` は JSON として有効かつ非 null の値を指定します。TLS やブラウザーチェックなどの Zone 設定は、既存の `settings` に `setting_id` と `value_json` を追加します。

`rulesets.rules_json` は JSON 配列を指定します。`id` を省略した場合は新しい Zone ルールセットを作成します。同じ Phase のエントリーポイントを複数管理することはできません。

`managed_rulesets` は Cloudflare が作成したルールセットを import して上書きする場合だけ使います。Terraform で新規作成することはありません。

## Free プランの上限

モジュールは代表的な Free プランの上限を検証します。

- Custom WAF ルール: 1 Zone あたり 5 ルール
- Rate Limiting: 1 Zone あたり 1 ルール、`period` と `mitigation_timeout` は 10 秒
- User-Agent Blocking: 1 Zone あたり 10 ルール

上限はプラン変更や Cloudflare 側の仕様変更で変わる可能性があります。apply 前に非公開環境の plan を確認してください。

## 使用例

`stacks/zone` と `examples/zone.tfvars.json.example` を参照してください。WAF ルールと Rate Limiting の例はリポジトリの README にあります。

```hcl
module "zone" {
  source = "../../modules/zone"

  account_id  = var.account_id
  zone        = var.zone
  dns_records = var.dns_records
  settings    = var.settings
  rulesets    = var.rulesets

  bot_management = {
    fight_mode          = true
    ai_bots_protection  = "block"
    crawler_protection  = "enabled"
    is_robots_txt_managed = true
  }
  url_normalization = {
    scope = "incoming"
    type  = "rfc3986"
  }
  managed_transforms = {
    response_headers = [
      { id = "add_security_headers", enabled = true },
      { id = "remove_x-powered-by_header", enabled = true },
    ]
  }
}
```
