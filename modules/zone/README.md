# Zone モジュール

`modules/zone` は、Cloudflare の Zone にある DNS、WAF、Bot 対策、TLS などを共通化したモジュールです。

Zone ごとに同じリソース定義を書くのは面倒なので、Terraform のコードは一つにして、実際の ID やルールだけ切り替える形にしています。

ただし、このモジュール自体は state を管理しません。実行するのは `stacks/zone` です。既存の Zone を import する仕組みや、ターゲットごとの state の分離もそちらに置いています。

## 何を設定できるのか

| 入力 | 内容 |
| --- | --- |
| `account_id` / `zone` | Account ID と既存 Zone の情報 |
| `dns_records` | DNS レコード |
| `settings` | HTTPS や TLS などの Zone 設定 |
| `rulesets` | 自分で作る WAF、Rate Limiting などの Ruleset |
| `managed_entrypoints` | Cloudflare 管理 Ruleset を実行する Phase の設定 |
| `existing_zone_ruleset_phases` | 既存 Phase の重複作成を防ぐための情報 |
| `bot_management` | Bot Fight Mode、AI クローラー対策、robots.txt |
| `url_normalization` / `dnssec` | URL 正規化と DNSSEC |
| `managed_transforms` | セキュリティヘッダーなどの変換 |
| `leaked_credential_check` | 漏洩資格情報の検知 |
| `authenticated_origin_pulls` | Cloudflare とオリジン間の認証 |
| `access_rules` | IP、ASN、国によるアクセス制御 |
| `user_agent_blocking_rules` | User-Agent による遮断 |

詳しい型や許容値は [variables.tf](variables.tf) にあります。`rulesets` などのマップキーは `custom` といったローカルの名前にして、実際のドメインや ID を含めないようにしています。

なお、`web_baseline` はこのモジュールの変数ではなく、`stacks/zone` 側の変数です。`stacks/zone/locals.tf` で TLS などの設定に変換してから、このモジュールへ渡します。

## 既存 Zone を取り込む

このリポジトリは、新しく Zone を量産するよりも**すでにある Cloudflare の設定を Terraform 管理へ移す**ことを想定しています。

手順としては以下のようになります。

1. Private 側で対象の匿名ターゲットと state キーを確認する。
2. [入力例](../../examples/zone.tfvars.json.example)を参考に、既存 Zone、DNS、Ruleset の ID を非公開の tfvars に設定する。
3. `stacks/zone/imports.tf` で既存リソースを取り込む。
4. まず plan を確認し、元の設定を勝手に変更しようとしていないことを確認する。
5. 問題なければ Private 側で apply する。

`terraform init -reconfigure` を state 移行と勘違いしないようにしてください。backend を初期化し直すだけです。間違った state キーを参照すると、存在するリソースが新規作成扱いになることがあります。

実行コマンドは [トップレベル README](../../README.md#plan-と-apply) にまとめています。

## DNS と Zone 設定

`dns_records` に既存レコードを入れる場合は `id` も指定します。import ID は `<zone_id>/<record_id>` 形式です。

Cloudflare の HTTP WAF を使いたい場合、レコードが **Proxied** になっていることも確認してください。DNS Only だと HTTP リクエストは Cloudflare の WAF を通りません。

TLS などは `settings` で設定します。

```hcl
settings = {
  https = {
    setting_id = "always_use_https"
    value_json = jsonencode("on")
  }
  tls = {
    setting_id = "min_tls_version"
    value_json = jsonencode("1.2")
  }
}
```

`value_json` は JSON として有効な文字列でなければならず、同じ `setting_id` を二重に指定することもできません。

このコードは HCL の書き方を示したものです。R2 に保存する設定は `tfvars.json` の形式にします。

### URL Normalization と DNSSEC

URL Normalization の `scope` は `incoming`、`both`、`none`、`type` は `cloudflare` または `rfc3986` を指定できます。

ただし Cloudflare 側のプランや Zone によって使えるかが変わります。API の `Sanitize Read` / `Sanitize Write` 権限がない場合も失敗します。

DNSSEC は `status = "active"` で有効にできますが、Cloudflare 側だけで終わりではありません。返された DS レコードをレジストラへ登録し、`dig +dnssec` などで実際に検証してください。

## WAF は Ruleset の所有権に注意

### Custom Rules と Rate Limiting

`rulesets` では `kind = "zone"` の Ruleset を定義します。既存のものを管理するなら `id` を指定し、新しく作るなら省略します。

`rules_json` は JSON の配列です。Free プランで代表的な制限は以下です。

| 種類 | 制限 |
| --- | --- |
| Custom WAF | 5 ルール / Zone |
| Rate Limiting | 1 ルール / Zone、`period = 10` |
| Rate Limiting の `characteristics` | `cf.colo.id` が必要 |
| `block` / `log` | `mitigation_timeout = 10` |
| チャレンジ系 | `mitigation_timeout = 0` |

Cloudflare 側に既存のルールがあっても上限に含まれます。Terraform 側に 1 件しか書いていないから安全、というわけではありません。

実際の HCL の例は [README の WAF 設定](../../README.md#waf-custom-rules) を参照してください。

### Free Managed Ruleset を消さない

少し厄介なのが Managed Ruleset です。Cloudflare が自動で適用しているものを、Terraform から空の Ruleset で上書きすると保護を消してしまう可能性があります。

そのため `http_request_firewall_managed` と `ddos_l7` は `managed_entrypoints` で別に扱っています。`http_response_firewall_managed` をここで管理することはできません。

`managed_entrypoints.id` は**管理 Ruleset 本体ではなく、Zone Phase のエントリーポイントの ID** です。`rules_json` には有効な `execute` ルールと、`action_parameters.id` に管理 Ruleset の ID が必要です。

空配列、有効な `execute` の欠落、無条件の `skip` は validation で拒否しています。とはいえチェックだけに頼らず、既存 Phase を import して無変更の plan を確認してから触る方が安全です。

### 同じ Phase を二つの state で管理しない

例えば `stacks/f2b` は API 向けの `http_request_firewall_custom` を所有しています。そこへ `stacks/zone` でも同じ Phase を作ると、どちらが正しい設定なのか分からなくなります。

`existing_zone_ruleset_phases` は Cloudflare の既存 Phase を確認して重複作成を拒否するためのものですが、**別 state の所有権までは検出できません**。

管理先を移す場合は両方の自動 apply を止め、旧 state から実リソースを削除せずに外して、新 state で import します。手順は [README の所有権移行](../../README.md#同じ-ruleset-を二つの-state-で管理しない)を参照してください。

## Bot 対策と TLS

`bot_management` には Bot Fight Mode のほか、`ai_bots_protection`、`crawler_protection`、`is_robots_txt_managed` などがあります。

ただ、Bot Fight Mode を全部の Zone で有効にすればよいわけではありません。API クライアントもチャレンジされる可能性があり、WAF Custom Rules の Skip では除外できません。

`managed_transforms` ではセキュリティヘッダーなどを設定できます。`leaked_credential_check` と `add_waf_credential_check_status_header` を組み合わせる場合も、必要な Transform を明示します。

`authenticated_origin_pulls` を有効にするときは、オリジン側の証明書と検証設定も必要です。Cloudflare 側だけ設定しても、保護が完成するわけではありません。

## IP / User-Agent による制御

`access_rules` は IP、ASN、国など、`user_agent_blocking_rules` は User-Agent の条件を管理します。

既存ルールには `id` を指定してください。Free の User-Agent Blocking は Zone ごとに 10 件までです。

User-Agent は誰でも変更できるので、これを認証の代わりに使うのは無理があります。単独の遮断条件にする場合も誤検知には注意してください。

## テスト

```sh
terraform -chdir=modules/zone init -backend=false -input=false
terraform -chdir=modules/zone test
```

これで入力値などを検査できますが、実際の Cloudflare API の権限や現在の既存ルールまでは確認できません。apply 前には Private 側で plan を見てください。

- [トップレベル README](../../README.md)
- [Zone の入力例](../../examples/zone.tfvars.json.example)
- [import の定義](../../stacks/zone/imports.tf)
