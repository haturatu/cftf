# Zone モジュール

`modules/zone` は、Cloudflare の **既存の一つの Zone** に対して、DNS、Zone 設定、Ruleset、Bot 対策、TLS、DNSSEC、各種セキュリティ機能を Terraform で管理するモジュールです。

本モジュールは **state と backend を管理しません**。実際の Zone の取り込みには `stacks/zone` を使用し、Zone ごとの非公開設定と、個別の state キーを渡します。

**重要:** 実際の Zone 名、Zone / Account ID、DNS レコード、Ruleset ID は公開コードへ書き込まないでください。入力例にはプレースホルダーだけを使用してください。plan や state には実値が含まれるため、公開しないでください。

## 入力の構成

| 入力 | 型 | 内容 |
| --- | --- | --- |
| `account_id` | `string` | Cloudflare Account ID |
| `zone` | `object` | 既存 Zone の ID、名前、種類、停止状態 |
| `dns_records` | `map(object)` | Zone の DNS レコード |
| `settings` | `map(object)` | TLS などの Zone 設定 |
| `rulesets` | `map(object)` | ユーザーが管理する Zone Phase のルールセット |
| `managed_entrypoints` | `map(object)` | Cloudflare 管理ルールを実行する Zone Phase のエントリーポイント |
| `existing_zone_ruleset_phases` | `set(string)` | 既存 Phase。重複作成の防止に使用 |
| `bot_management` | `object` | Bot Fight Mode、AI クローラー対策、管理 robots.txt |
| `url_normalization` | `object` | URL の正規化 |
| `dnssec` | `object` | DNSSEC の状態 |
| `managed_transforms` | `object` | セキュリティヘッダー等 |
| `leaked_credential_check` | `bool` | 漏洩資格情報の検査 |
| `authenticated_origin_pulls` | `bool` | Cloudflare からオリジンへの認証 |
| `access_rules` | `map(object)` | IP / ASN / 国のアクセス制御 |
| `user_agent_blocking_rules` | `map(object)` | User-Agent に基づくアクセス制御 |

各 `map` のキーには、`custom`、`rate_limit` などの**安定したローカル名**を使用します。ドメイン名や実 ID を含めないでください。正確な型、許容値、件数制限は [variables.tf](variables.tf) を参照してください。

`web_baseline` は **モジュールの入力ではなく、呼び出し元の `stacks/zone` の入力**です。`stacks/zone/locals.tf` で標準の TLS / HTTPS / BIC 設定へ変換したうえで、本モジュールの `settings` などに渡されます。

## 既存 Zone の管理を始める

1. Private 側の許可リストで、対象 Zone の匿名ターゲットと正しい state キーを確認します。
2. [Zone の入力例](../../examples/zone.tfvars.json.example)を参考に、実 ID と設定を非公開の `tfvars.json` に定義します。
3. 既存 DNS、Ruleset、Access Rule には正しい ID を指定します。`stacks/zone/imports.tf` は、ID を持つ既存リソースを import します。
4. Private 側で plan を作成し、**意図しない作成・削除・更新のないこと**を確認します。
5. 既存設定と Terraform の差分が理解できてから apply します。

実際の操作は [トップレベル README](../../README.md#設定を-plan--apply-する) を参照してください。

**注意:** `terraform init -reconfigure` は state の移行ではありません。初期取り込みで state キーを誤ると、既存リソースが存在しないように見えて、新規作成や削除を計画する場合があります。

## Zone 設定と DNS

### DNS レコード

`dns_records` には、この Zone で Terraform が所有する DNS レコードを指定します。既存レコードでは `id` を含めます。`stacks/zone/imports.tf` は `<zone_id>/<record_id>` 形式で取り込みます。

Cloudflare の **Proxied** が無効な DNS Only レコードのトラフィックは、Cloudflare HTTP WAF の保護を通りません。DNS を切り替える前に接続経路とオリジンの公開状態を確認してください。

### Zone 設定

`settings` の各項目には `setting_id` と `value_json` を指定します。`value_json` は**JSON として有効な非 null 文字列**でなければなりません。同じ `setting_id` の重複は拒否されます。

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

この例は、HCL で表現した**モジュール入力の一部**です。実際に R2 に保管する場合は、Terraform の `tfvars.json` 形式に変換して他の必須項目と合わせます。

`web_baseline` を使用する場合、呼び出し元が `ssl=strict`、`always_use_https=on`、`min_tls_version=1.2`、`tls_1_3=on`、`browser_check=on` を管理します。既存の `settings` に同じ `setting_id` があっても、ベースライン値が優先されます。

### URL Normalization と DNSSEC

`url_normalization` の `scope` は `incoming` / `both` / `none`、`type` は `cloudflare` / `rfc3986` に対応します。利用には対象 Zone の API 機能と Zone の `Sanitize Read` / `Sanitize Write` 権限が必要です。認可されていない場合は 403 になります。

`dnssec` は `status = "active"` または `"disabled"` を指定します。Cloudflare 側で有効にした後は、返された DS レコードをレジストラに設定し、`dig +dnssec` で信頼チェーンを確認してください。

## WAF とルールセット

### Custom Rules と Rate Limiting

`rulesets` は、利用者が所有する Zone エントリーポイントを定義します。`kind = "zone"` を使用し、既存リソースならその Ruleset ID を `id` に指定します。`id` がない場合は新規作成の対象になります。

`rules_json` にはルールの **JSON 配列**を格納します。同じ Zone の同じ Phase を複数のルールセットで管理することはできません。

Free プランに合わせた代表的な制限:

| Phase | 制限 |
| --- | --- |
| `http_request_firewall_custom` | 5 ルール / Zone |
| `http_ratelimit` | 1 ルール / Zone。`period = 10` 秒 |
| `http_ratelimit` の `characteristics` | `cf.colo.id` を含める |
| Rate Limit の `block` / `log` | `mitigation_timeout = 10` |
| Rate Limit のチャレンジ系 | `mitigation_timeout = 0`（request throttling） |

**注意:** 件数は、Cloudflare の Zone / Phase にすでに存在するルールも含めて確認します。モジュールの validation は設定値の形式と一部の上限を検証しますが、別の Terraform state の所有権までは判定できません。

HCL の例と、実際に採用する場合の注意点は [トップレベル README の WAF 設定](../../README.md#waf-custom-rules)を参照してください。

### Managed Ruleset の実行設定

`http_request_firewall_managed` / `http_response_firewall_managed` / `ddos_l7` は、通常の `rulesets` では拒否します。このモジュールの `managed_entrypoints` が対応するのは **`http_request_firewall_managed` と `ddos_l7`** の Zone エントリーポイントです。`http_response_firewall_managed` をここで管理することはできません。

`managed_entrypoints.id` は **管理ルールセット本体の ID ではなく、Zone Phase エントリーポイントの ID** です。`rules_json` には少なくとも一つの有効な `execute` ルール（`expression` と32桁の `action_parameters.id` を持つ）を含めます。

次のような入力は validation が拒否します。

- 空のルール配列
- 有効な `execute` ルールが存在しない配列
- 無条件の `skip`（`expression = "true"`）

Free Managed Ruleset と HTTP DDoS Protection は Cloudflare が自動適用するため、通常は明示的な設定を追加しないでください。変更が必要なら、既存 Phase を import し、まず無変更 plan を確認してください。

### Phase の重複を防ぐ

`existing_zone_ruleset_phases` は Cloudflare 側にすでに存在する Zone Phase です。呼び出し元 `stacks/zone` が `cloudflare_rulesets` データソースから設定します。`id` のない新規エントリーポイントが既存 Phase と重複する場合は拒否します。

ただし、この検査は別の Terraform state の**所有権**を検出するものではありません。`stacks/f2b` と `stacks/zone` の間で `http_request_firewall_custom` の管理を移す場合は、両方の自動 apply を停止し、旧 state から実体を削除せずに外してから新 state へ import してください。

[所有権移行の手順](../../README.md#同じ-phase-の所有権を分離する)を参照してください。

## Bot、TLS、ヘッダー

`bot_management` は、値を指定した場合だけ設定します。主なフィールドは `fight_mode`、`ai_bots_protection`、`crawler_protection`、`is_robots_txt_managed`、`ai_training`、`ai_user`、`aisearch` です。

**Bot Fight Mode は WAF Custom Rules の Skip では除外できません。** API やモバイルクライアントが利用する Zone で有効にすると、正常な通信をチャレンジする場合があります。

`managed_transforms` は `request_headers` / `response_headers` に、Transform ID と `enabled` を指定します。空の設定は validation で拒否します。`leaked_credential_check` は `add_waf_credential_check_status_header` との併用を検討してください。

`authenticated_origin_pulls` は、オリジン側の証明書と検証設定がすでに用意されている場合だけ有効にします。Cloudflare 側の設定だけではオリジンを保護できません。

## IP / User-Agent アクセスルール

`access_rules` は IP、IPv6、CIDR、ASN、国などのターゲットを管理します。`user_agent_blocking_rules` は User-Agent に基づくルールです。いずれも既存リソースなら正しい `id` を指定して import します。

Free プランの User-Agent Blocking は 10 ルール / Zone です。`mode` は `block`、`challenge`、`whitelist`、`js_challenge`、`managed_challenge` など、モジュールで検証する値から指定してください。

**注意:** User-Agent はクライアントが任意に変更できます。これだけで認証や確実な攻撃者識別を行わないでください。

## 検証と関連資料

認証情報を使用せず、モジュールの validation と Terraform テストを実行できます。

```sh
terraform -chdir=modules/zone init -backend=false -input=false
terraform -chdir=modules/zone test
```

このテストは実在する Cloudflare API の権限や全ルールの実行結果を検査しません。**本番への apply 前には Private 側で plan を確認する必要があります。**

- [運用・セキュリティ設定の全体像](../../README.md)
- [Zone の入力例](../../examples/zone.tfvars.json.example)
- [Zone stack の import 定義](../../stacks/zone/imports.tf)
- [Cloudflare WAF のプラン別機能](https://developers.cloudflare.com/waf/)
- [Cloudflare Bot Fight Mode](https://developers.cloudflare.com/bots/get-started/bot-fight-mode/)
