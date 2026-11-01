<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Cloudflare の Terraform 管理](#cloudflare-%E3%81%AE-terraform-%E7%AE%A1%E7%90%86)
  - [構成](#%E6%A7%8B%E6%88%90)
  - [Free プランのセキュリティ機能](#free-%E3%83%97%E3%83%A9%E3%83%B3%E3%81%AE%E3%82%BB%E3%82%AD%E3%83%A5%E3%83%AA%E3%83%86%E3%82%A3%E6%A9%9F%E8%83%BD)
    - [WAF Custom Rules と Rate Limiting](#waf-custom-rules-%E3%81%A8-rate-limiting)
    - [Bot 対策](#bot-%E5%AF%BE%E7%AD%96)
    - [TLS とセキュリティヘッダー](#tls-%E3%81%A8%E3%82%BB%E3%82%AD%E3%83%A5%E3%83%AA%E3%83%86%E3%82%A3%E3%83%98%E3%83%83%E3%83%80%E3%83%BC)
    - [ルールセットの所有権](#%E3%83%AB%E3%83%BC%E3%83%AB%E3%82%BB%E3%83%83%E3%83%88%E3%81%AE%E6%89%80%E6%9C%89%E6%A8%A9)
    - [Free プランで使えないもの](#free-%E3%83%97%E3%83%A9%E3%83%B3%E3%81%A7%E4%BD%BF%E3%81%88%E3%81%AA%E3%81%84%E3%82%82%E3%81%AE)
  - [Account 単位のセキュリティ](#account-%E5%8D%98%E4%BD%8D%E3%81%AE%E3%82%BB%E3%82%AD%E3%83%A5%E3%83%AA%E3%83%86%E3%82%A3)
  - [PR のラベルから apply する流れ](#pr-%E3%81%AE%E3%83%A9%E3%83%99%E3%83%AB%E3%81%8B%E3%82%89-apply-%E3%81%99%E3%82%8B%E6%B5%81%E3%82%8C)
  - [R2 の設定リビジョン](#r2-%E3%81%AE%E8%A8%AD%E5%AE%9A%E3%83%AA%E3%83%93%E3%82%B8%E3%83%A7%E3%83%B3)
  - [手動で plan する](#%E6%89%8B%E5%8B%95%E3%81%A7-plan-%E3%81%99%E3%82%8B)
    - [Setup](#setup)
    - [Usage](#usage)
    - [plan / apply](#plan--apply)
  - [検証と初回取り込み](#%E6%A4%9C%E8%A8%BC%E3%81%A8%E5%88%9D%E5%9B%9E%E5%8F%96%E3%82%8A%E8%BE%BC%E3%81%BF)
    - [Setup](#setup-1)
    - [Tests](#tests)
  - [Bootstrap と復旧](#bootstrap-%E3%81%A8%E5%BE%A9%E6%97%A7)
  - [参考資料](#%E5%8F%82%E8%80%83%E8%B3%87%E6%96%99)
  - [Fail2ban API](#fail2ban-api)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Cloudflare の Terraform 管理

Terraform のコードは Git、設定値と Worker ソースは非公開 R2、state は別の専用 R2 バケットで管理します。  
オブジェクトストレージ側の `R2` に依存した気持ち悪いIaC化。ドメイン名、Zone ID、バケット名、認証情報は公開コードに含めないようにした結果の末路。  
基本的な入力値を `R2` のオブジェクトストレージ側に全て置いてパブリック化したレポジトリ。 `apply` 自体は別レポジトリ側を呼び出して実行。このレポジトリから非公開レポジトリ側の `Github Runner` に流して `apply` を実行させる。  

## 構成

```text
cftf/
├── .github/workflows/         # 非機密の検証、ラベル承認、マージと実行要求
├── stacks/
│   ├── zone/                 # 全 Zone が共有する root
│   ├── security-account/     # IP リスト・Turnstile の Account 共通 root
│   ├── r2/
│   ├── workers/
│   └── f2b/                   # 公開 API の基盤（D1・Access・カスタムドメイン）
├── modules/
│   ├── zone/                 # 既存リソースアドレスを維持する共通定義
│   └── account-security/     # Account 単位の IP リスト・Turnstile
├── bootstrap/backend/        # State・Config バケットの初期構築と復旧専用
├── scripts/tf.sh             # 共通の手動実行窓口
├── examples/
└── .private/                 # Git 管理外の一時データと診断ログ
```

Zone の違いは非公開の入力値と state キーだけです。`zone-001` などの匿名ターゲットを、Private 側の許可リストで管理します。Zone の追加時に Terraform ファイルを複製する必要はありません。

`stacks/zone` は `module.zone` のリソースアドレスを維持します。各ターゲットの `TF_DATA_DIR` と既存の state キーを分け、同じ root を使っても state が混ざらない構成です。`init -reconfigure` は選択した backend を初期化する処理であり、state の移行は行いません。

## Free プランのセキュリティ機能

2026-11-01 時点の Cloudflare Free プランで、Web フロントエンドの保護に使える主な機能と Terraform の対応です。Free の上限はプランや Cloudflare 側の仕様変更で変わるため、apply 前に非公開環境の plan を確認してください。

| 機能 | Free プランの範囲 | Terraform |
| --- | --- | --- |
| Cloudflare Free Managed Ruleset | 既知の重大脆弱性を自動防御 | 自動適用。上書きする場合だけ `managed_entrypoints` で Phase エントリーポイントを import |
| WAF Custom Rules | 5 ルール / Zone | `rulesets` の `http_request_firewall_custom` |
| WAF Rate Limiting | 1 ルール / Zone、10 秒 | `rulesets` の `http_ratelimit` |
| HTTP DDoS Protection | 自動防御 | 原則不要。上書きする場合だけ `managed_entrypoints` の `ddos_l7` |
| IP Access Rules | 50,000 件 / Account | `access_rules` |
| IP Custom Lists | 1 リスト / Account | `stacks/security-account` の `ip_lists` |
| User Agent Blocking | 10 件 / Zone | `user_agent_blocking_rules` |
| Leaked Credentials Detection | 漏洩パスワードの検出 | `leaked_credential_check` |
| Bot Fight Mode | ドメイン全体に適用 | `bot_management.fight_mode` |
| Block AI Bots | AI クローラーを遮断 | `bot_management.ai_bots_protection` |
| AI Labyrinth | AI クローラー向けリンク迷路 | `bot_management.crawler_protection` |
| Managed robots.txt | AI クローラーへのポリシー提示 | `bot_management.is_robots_txt_managed` |
| Turnstile | 20 ウィジェット / Account | `stacks/security-account` の `turnstile_widgets` |
| URL Normalization | WAF 評価前の URL 正規化 | `url_normalization` |
| DNSSEC | DNS 応答の改ざん対策 | `dnssec` |
| Managed Transforms | セキュリティヘッダー等 | `managed_transforms` |
| Authenticated Origin Pulls | Cloudflare 経由の mTLS 確認 | `authenticated_origin_pulls` |
| Browser Integrity Check | 不審な HTTP ヘッダー等の検査 | `settings` の `browser_check` |
| Under Attack Mode | 緊急時の Managed Challenge | `settings` の `security_level` |
| Email Address Obfuscation | メールアドレス収集の抑制 | `settings` の `email_obfuscation` |
| Hotlink Protection | 画像の外部直リンク防止 | `settings` の `hotlink_protection` |
| Replace insecure JS | 危険な JS 配信元の置換 | `settings` の `replace_insecure_js` |
| Client-side Security | スクリプト監視のみ | Free は Content Security Rules が 0 のため Terraform 管理対象外 |
| Configuration / Transform / Cache Rules | 各 10 ルール / Zone | `rulesets` の各 Phase |
| Security Analytics / Events | 無料の分析機能 | Terraform 管理対象外 |
| Cloudflare Access / Tunnel | 無料枠あり | 既存の `stacks/f2b` などで管理 |

Free Managed Ruleset と HTTP DDoS Protection は Cloudflare が自動で有効化します。Terraform で再作成する必要はありません。ルールの上書きや無効化が必要な場合だけ、Phase の Zone エントリーポイント（`kind = "zone"`）を `managed_entrypoints` で管理します。`id` は管理ルールセット本体（`kind = "managed"`）ではなく、Zone エントリーポイント Ruleset の ID です。`rules_json` には管理ルールセット ID を `action_parameters.id` に持つ `execute` ルールを記述します。空の `rules_json` は管理ルールセットの実行を消すおそれがあるため、モジュールが拒否します。さらに、少なくとも 1 件の有効な `execute` ルール（`expression` と 32 文字の `action_parameters.id` を持つ）を必須とし、無条件の `skip` ルール（`expression = "true"`）も拒否します。通常の Custom Rules は `rulesets` を使います。

`action_parameters.id` には、Free Managed Ruleset（2026-11-01 時点の例: `77454fe2d30c4220b5701f6fdfb893ba`）や L7 DDoS（同: `4d21379b4f9f4bb088e0729962c8b3cf`）など、対象プランで利用できる管理 Ruleset の ID を指定します。ID は Cloudflare API の rulesets 一覧で確認してください。

Free Managed Ruleset は自動適用されるため、通常は `managed_entrypoints` を作成する必要はありません。カスタマイズする場合も、まず既存の Phase エントリーポイントの有無を確認し、存在する場合は import して無変更 plan を確認してください。エントリーポイントが存在しない場合の新規作成は、管理ルールセットが二重実行されないことを非公開環境で確認してから行います。

DNSSEC は Cloudflare 側の有効化だけでは信頼チェーンが完成しません。apply 後に `dnssec_ds` 出力をレジストラへ登録し、`dig +dnssec` などで到達性を確認してください。この確認は Terraform や CI の範囲外です。

### WAF Custom Rules と Rate Limiting

`rulesets` は既存ルールセットを import する場合は `id` を指定し、新規作成する場合は省略します。同じ Phase のエントリーポイントを複数管理することはできません。`http_request_firewall_managed`、`http_response_firewall_managed`、`ddos_l7` は Managed Ruleset の実行設定を消すおそれがあるため、通常の `rulesets` では管理せず `managed_entrypoints` を使います。Free プランの 5 ルールを有効に使う例です。

```hcl
module "zone" {
  # ...
  rulesets = {
    custom = {
      name  = "Custom WAF"
      kind  = "zone"
      phase = "http_request_firewall_custom"
      rules_json = jsonencode([
        {
          ref         = "block_sensitive_paths"
          description = "Block requests for sensitive files"
          expression  = "(http.request.uri.path eq \"/.env\") or (http.request.uri.path contains \"/.git/\")"
          action      = "block"
          enabled     = true
        },
        {
          ref         = "block_nonstandard_ports"
          description = "Block non-standard HTTP ports"
          expression  = "not (cf.edge.server_port in {80 443})"
          action      = "block"
          enabled     = true
        },
      ])
    }
  }
}
```

Rate Limiting は 1 Zone に 1 ルール、`period` は 10 秒です。`characteristics` には `cf.colo.id` が必須です。`requests_per_period` は API の実利用量に合わせて調整します。`block` / `log` は `mitigation_timeout = 10`、`challenge` / `js_challenge` / `managed_challenge` は Free プランの request throttling により `mitigation_timeout = 0` を指定します。

```hcl
rulesets = {
  rate_limit = {
    name  = "API Rate Limiting"
    kind  = "zone"
    phase = "http_ratelimit"
    rules_json = jsonencode([{
      ref         = "api_ip_limit"
      description = "Limit API requests per IP"
      action      = "block"
      expression  = "starts_with(http.request.uri.path, \"/api/\")"
      enabled     = true
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 10
        requests_per_period = 30
        mitigation_timeout  = 10
      }
    }])
  }
}
```

### Bot 対策

`bot_management.fight_mode` はブラウザーで利用する Web サイト向けです。REST API が中心の Zone では無効にし、WAF、Cloudflare Access、Rate Limiting を組み合わせます。Bot Fight Mode は WAF の Skip ルールでは除外できません。

AI クローラー対策は `ai_bots_protection`、`crawler_protection`、`is_robots_txt_managed` で設定します。`ai_training`、`ai_user`、`aisearch`、`cf_robots_variant`、`bot_preference_sync_enabled` を使うと、管理 robots.txt のポリシーを細かく指定できます。

`bot_management` は Free プランで利用できる設定だけを公開します。Super Bot Fight Mode、Bot Management の ML スコア、`jsd_api_results_enabled`、`auto_update_model`、`bm_cookie_enabled`、`suppress_session_score`、`optimize_wordpress` などは有料プラン向けのため含めていません。JavaScript Detections は Bot Fight Mode 有効時に自動で有効になり、Free では個別に無効化できません。

Turnstile は Cloudflare の DNS や WAF とは独立して、ログイン、登録、問い合わせ、フォーム送信だけを保護できます。サイト全体の Bot Fight Mode を有効にしたくない場合に適しています。

### TLS とセキュリティヘッダー

TLS とブラウザー保護は既存の `settings` で管理します。代表的な設定です。値は Zone の構成に合わせて調整してください。

| setting_id | 推奨値 | 内容 |
| --- | --- | --- |
| `ssl` | `"strict"` | Full (strict) SSL/TLS |
| `always_use_https` | `"on"` | HTTP から HTTPS へのリダイレクト |
| `automatic_https_rewrites` | `"on"` | 混在コンテンツの HTTPS 書き換え |
| `min_tls_version` | `"1.2"` | 最低 TLS バージョン |
| `tls_1_3` | `"on"` | TLS 1.3 |
| `security_header` | HSTS を有効化 | `strict_transport_security` |
| `browser_check` | `"on"` | Browser Integrity Check |
| `security_level` | `"medium"` | 緊急時だけ `"under_attack"` |
| `email_obfuscation` | `"on"` | メールアドレスの難読化 |
| `hotlink_protection` | `"on"` | 画像の直リンク防止。不要なら `"off"` |
| `replace_insecure_js` | `"on"` | 危険な JS の置換 |
| `opportunistic_encryption` | `"on"` | Opportunistic Encryption |
| `server_side_exclude` | `"on"` | Server-Side Excludes |

HSTS の `preload` は、すべてのサブドメインが HTTPS で安定して動作することを確認してから有効にします。`managed_transforms` の `add_security_headers` は `X-Content-Type-Options`、`X-Frame-Options`、`Referrer-Policy` などを追加します。CSP などサイト固有のヘッダーは `rulesets` の `http_response_headers_transform` で設定できます。

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
  hsts = {
    setting_id = "security_header"
    value_json = jsonencode({
      strict_transport_security = {
        enabled            = true
        max_age            = 31536000
        include_subdomains = true
        preload            = false
        nosniff            = true
      }
    })
  }
}
```

### ルールセットの所有権

Cloudflare の Zone では、同じ Phase のエントリーポイントルールセットを複数の Terraform state で管理しないでください。`stacks/zone` の `rulesets` は Phase の重複を検証します。

`stacks/f2b` は対象 Zone の `http_request_firewall_custom` を所有し、API クライアント向けの BIC Skip ルールを管理します。同じ Zone を `stacks/zone` でも管理する場合、`stacks/zone` 側に同じ Phase のルールセットを追加しないでください。

所有権を `stacks/zone` へ移す場合は、二重管理の期間を作らないために次の順序で行います。

1. 両スタックの自動 apply を停止する。
2. Cloudflare API または既存 state から、対象の `http_request_firewall_custom` ルールセット ID を取得する。
3. `stacks/f2b` で `manage_api_browser_check = false` を設定し、Private 環境で `terraform state rm 'cloudflare_ruleset.api_browser_checks[0]'` を実行する。API 上のルールは削除しない。
4. `stacks/zone` の非公開設定に、その ID と現在のルールを含む `rulesets` エントリを追加する。
5. `stacks/zone` を plan し、無変更であることを確認してから apply する。

`stacks/zone` は `cloudflare_rulesets` データソースで既存の Zone エントリーポイントを検出し、`id` なしの重複作成を plan 時に拒否します。データソースだけでは別 state の所有権までは判定できないため、移管時は自動 apply を停止し、上記の順序を守ってください。`stacks/f2b` のリソースには `prevent_destroy` を付けています。手順を誤って削除しようとすると plan が失敗します。`imports.tf` は、既存リソースの `id` を指定した場合だけ import し、新規作成するリソースには import を適用しません。Provider v5.28.1 の Ruleset import ID は `zones/<zone_id>/<ruleset_id>` です。

Terraform の検証は変数と plan の範囲です。WAF ルールの削除・無効化や管理 Ruleset の実行喪失を最終的に防ぐには、Private CI の plan 検査に「保護ルールの削除・無効化を拒否する」条件を追加してください。

### Free プランで使えないもの

次の機能は Free プランの対象外です。Terraform の定義を追加しても API で失敗するため、採用しません。

| 機能 | 必要なプラン |
| --- | --- |
| Super Bot Fight Mode | Pro 以上 |
| Bot Management の ML スコア (`cf.bot_management.score`) | Enterprise |
| WAF Attack Score | 有料プラン |
| Cloudflare Managed Ruleset のフル版 | Pro 以上 |
| OWASP Core Ruleset | Pro 以上 |
| WAF の正規表現 `matches` | 有料プラン |
| Advanced Rate Limiting | 有料追加機能 |
| Managed IP Lists | Enterprise |
| ASN・Hostname Custom Lists | Enterprise |
| Zone Lockdown | Pro 以上 |
| Sensitive Data Detection | Enterprise |
| Malicious Uploads Detection | 有料追加機能 |
| Account-level WAF Rulesets | Enterprise |
| API Schema Validation の新規構成 | Enterprise 向け |

Cloudflare Access、Tunnel、DNSSEC、Security Analytics は無料枠で利用できます。Access と Tunnel は `stacks/f2b` の構成を参照してください。

## Account 単位のセキュリティ

IP リストと Turnstile は Account 単位の資源です。Zone ごとの state に置くと二重作成や所有権の衝突が起きるため、`stacks/security-account` で独立して管理します。

```text
stacks/security-account/
├── backend.tf
├── imports.tf
├── main.tf
├── variables.tf
└── versions.tf
```

Free プランでは IP リストは 1 つ、Turnstile は 20 ウィジェットまでです。IP リストの `name` は小文字英数字とアンダースコアの 1〜50 文字で指定し、WAF の式から `ip.src in $allowed_ips` のように参照します。1 リストあたり最大 10,000 項目です。IP は IPv4・IPv6・CIDR の実体として検証されます。既存のリストやウィジェットを管理する場合は、`import_id` にリスト ID または sitekey を指定します。

既存 IP リストを import するときは `items` を省略してください。Provider v5.28.1 では `items` を指定するとリスト全体を上書きするため、省略時は既存項目を維持し、明示的な空配列だけが全削除になります。Turnstile の Enterprise 専用設定（`bot_fight_mode`、`ephemeral_id`、`offlabel`）は Free 向けモジュールでは公開していません。

Turnstile の secret は Terraform state に保存されます。state は非公開 R2 で管理し、ログや plan を公開しないでください。`examples/security-account.tfvars.json.example` に最小構成の例があります。

## PR のラベルから apply する流れ

1. PR の `Terraform checks` が、認証情報なしでフォーマット、構文、モックテストを検証します。
2. 許可された利用者が `terraform-apply` ラベルを付け、その時点の head SHA を承認します。
3. チェック成功とレビュー状態を確認して squash merge します。PR 更新時はラベルと承認を無効にします。
4. マージ後の確定 SHA を Private リポジトリ `haturatu/cftf-deploy` に通知します。
5. Private CI が承認、マージ SHA、最新の master を再確認し、R2 の固定リビジョンを取得します。
6. 全ターゲットの plan を検査し、削除・置き換えを拒否したうえで保存済み plan を適用します。

公開側へ返すのは固定の成功・失敗・後続コミットによる置き換え通知だけです。plan 本文、リソース種別、件数、ドメイン、ID は公開しません。公開側で本番の Terraform コードを実行せず、Private CI も PR ブランチではなくマージ済みコミットだけを使います。

`AUTOMATION_ENABLED` と Private 側の `DEPLOY_ENABLED` は初期状態では `false` です。無料枠の復旧、GitHub App の設定、本番設定の確認が済むまで有効にしません。GitHub App の作成手順と Secrets の設定方法は Private リポジトリの README にあります。

## R2 の設定リビジョン

非公開 Config バケットの `revisions/<revision>/` に、次のファイルを保管します。

```text
backend.hcl
zones/<anonymous-target>.tfvars.json
security-account.tfvars.json
r2.tfvars.json
workers.tfvars.json
workers/...
manifest.json
```

`backend.hcl` は共通のバケット名、エンドポイント、S3 互換設定を持ち、state キーを含みません。実行側の許可リストがターゲットごとの既存キーを指定します。Config と State のバケットは別にします。

JSON 形式の tfvars は Terraform 標準の入力形式です。Zone 設定の動的な値は `value_json`、ルール配列は `rules_json` として保持します。Bot、URL Normalization、DNSSEC、Managed Transforms、IP Access Rules なども同じ Zone の tfvars に追加します。Worker のソースパスはダウンロード先の絶対パスに置き換えます。`security-account.tfvars.json` は Account 共通の IP リストと Turnstile を保持し、Zone の state とは分けます。

CI は Private 側で固定したリビジョンと manifest の SHA-256 を検証し、さらに各ファイルのサイズと SHA-256 を検証します。既存リビジョンを上書きせず、設定変更時は新しいリビジョンを発行して承認します。設定ファイルそのものを GitHub Secrets や Git に保存する必要はありません。

Config 取得用キーは読み取り専用、State 用キーはそのバケットの読み書き用として分離します。Cloudflare Provider の認証は別の CI 専用トークンです。GitHub App の秘密鍵を含め、実値は Public リポジトリへ置きません。

## 手動で plan する

Arch Linux 系では、次のコマンドで依存パッケージをインストールします。

### Setup
```sh
sudo pacman -S --needed \
  bash coreutils git github-cli jq terraform python python-pip aws-cli
```

Terraform は CI と同じ `1.15.9` を使います。`gh` コマンドのパッケージ名は `github-cli` です。

Bash の Tab 補完は次のコマンドで有効にします。次回以降も使う場合は、このファイルを絶対パスで読み込む行を `~/.bashrc` に追加してください。

```bash
source ./scripts/tf-completion.bash
```

`./scripts/tf.sh <Tab>` のターゲット候補は、補完のたびに Private 側の `deployment/config.json` から取得します。取得に認証情報や R2 への接続は不要です。許可リストを編集すると再読み込みなしで反映されます。2 つ目の引数は `plan` と `apply` を補完します。Private 側の配置を変更する場合は、補完前に `CFTF_DEPLOY_DIR` を export してください。

手動実行も、Private 側の共通処理を呼び出して R2 から設定を取得します。隣接する `cftf-deploy` の checkout と、その仮想環境を準備してください。配置が異なる場合は `CFTF_DEPLOY_DIR` と `CFTF_DEPLOY_PYTHON` を指定します。

`.env.example` にある標準名で認証情報と承認済みの R2 リビジョンを設定し、リポジトリルートから読み込みます。既存の `.env` は上書きしないでください。

ローカルの操作は、基本的に `terraform` のラッパーシェル経由で操作します。  

### Usage
```sh
$ ./scripts/tf.sh
ERROR: usage: scripts/tf.sh <approved-target> <plan|apply>
```

### plan / apply
```sh
umask 077
set -a
. ./.env
set +a
./scripts/tf.sh zone-001 plan
./scripts/tf.sh zone-002 plan
./scripts/tf.sh r2 plan
./scripts/tf.sh workers plan
./scripts/tf.sh security-account plan
```

`apply` を指定すると、同じ処理で plan を作成・検査してから、その保存済み plan を適用します。任意の Terraform オプションや未知のターゲットは受け付けません。

```sh
./scripts/tf.sh zone-001 apply
```

通常出力は固定の状態のみです。詳細ログ、設定の一時ファイル、保存した plan は `.private/runtime/` に置きます。アクセス権はディレクトリ `700`、ファイル `600` とし、公開しないでください。CI はローカル端末の `.private/` を参照しません。

## 検証と初回取り込み

GitHub API はモックし、ネットワーク接続なしで承認、マージ、実行要求を検証します。

依存関係としてシェルの静的解析には `shellcheck`、Workflow の検証には `actionlint` を使います。

### Setup
```sh
sudo pacman -S --needed shellcheck shfmt actionlint
```

### Tests
```sh
terraform fmt -check -recursive
.github/scripts/control.test.sh
./scripts/tf.test.sh
shellcheck -x scripts/*.sh scripts/*.bash .github/scripts/*.sh
shfmt -d -i 2 -ci -sr scripts/*.sh scripts/*.bash .github/scripts/*.sh
terraform -chdir=modules/zone init -backend=false -input=false
terraform -chdir=modules/zone test
terraform -chdir=modules/account-security init -backend=false -input=false
terraform -chdir=modules/account-security test
terraform -chdir=bootstrap/backend init -backend=false -input=false
terraform -chdir=bootstrap/backend test
```

Workflow の `queue: max` は actionlint `1.7.12` が認識しないため、その警告だけを除外します。

```sh
actionlint -ignore 'unexpected key "queue" for "concurrency" section' \
  .github/workflows/*.yml
```

[Dependabot の設定](.github/dependabot.yml)は、GitHub Actions と Terraform Provider の通常のバージョン更新を毎月 1 日の日本時間 09:00 に確認します。種類ごとに更新をまとめ、未処理の更新 PR は各 1 件に制限します。更新 PR は通常のレビューで扱います。セキュリティ更新の有効化状態は変更せず、その更新頻度はこの月次設定とは別です。

Provider 更新時は、Private 側の `deployment/config.json` の `provider_version` と `trust/cloudflare.lock.hcl` も更新して整合性を確認します。Terraform CLI のバージョンは、両リポジトリの Workflow と Private 側の設定を手動で揃えます。

各 stack には Provider lock ファイルを置き、Provider を固定します。R2 と Worker の入力は使用する機能に合わせた `map(object(...))` で定義し、ID、リージョン、参照先、公開設定を検証します。Worker は Terraform で引き続き管理し、既存の Secret を保持します。

`imports.tf` は未取り込みの既存リソースのために残しています。取り込みと各ターゲットの plan 照合が完了した後に削除できます。取り込み前に削除すると、新規作成として扱われるため削除しないでください。

R2 の公開設定、ライフサイクル、CORS は固定 Provider で import 非対応です。初回に追加として表示されても、既存設定 API への書き込みである場合があります。初回の差分は非公開環境で確認してください。

## Bootstrap と復旧

`bootstrap/backend` は日常の CI 対象に含めません。State と Config バケットの初期作成や復旧にだけ使います。既存の bootstrap state とバケットを二重作成せず、専用の非公開設定と既存キーを使って操作してください。

R2 に S3 のバージョニング機能はないため、state、bootstrap の復旧情報、認証情報のバックアップは別の非公開ストレージへ保管します。設定値の通常運用には R2 のリビジョンを使い、端末上の移行元ファイルはバックアップとしてのみ扱います。

## 参考資料

- [Terraform 設計ガイドライン](https://future-architect.github.io/arch-guidelines/documents/forTerraform/terraform_guidelines.html)
- [Cloudflare R2 backend](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [GitHub Actions の実行イベント](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)

## Fail2ban API

`stacks/f2b` は D1、Access の組織・Service Token・収集ポリシー、カスタムドメイン、WAF を管理します。新規の `f2b` ターゲットは専用 state を使用します。Worker のスクリプト、バインディング、バージョンは公開 `f2b-api` リポジトリの GitHub Actions が Wrangler で配信し、このスタックはスクリプトを管理しません。アプリケーションのビルド結果は非公開 R2 の設定リビジョンに含めません。`terraform output -json deployment_config` を非公開で取得し、`f2b-api` の `production` 環境の Secret `F2B_DEPLOY_CONFIG` に設定します。

両 Worker の `workers.dev` とプレビュー URL は Wrangler 設定で無効にし、収集ドメインを Service Auth で保護します。収集元ごとに Service Token を発行し、API は Cloudflare が検証した Access アプリケーション AUD と設定上の Jail 範囲を照合します。認証用の Secret は Terraform state と各収集サーバーの保護された設定だけに保存します。D1 のスキーマ変更は `f2b-api/migrations` を適用します。

`stacks/f2b` は対象 Zone の `http_request_firewall_custom` も所有します。`manage_api_browser_check` は既定で `true` です。所有権を `stacks/zone` へ移す手順は「Free プランのセキュリティ機能」の「ルールセットの所有権」を参照してください。

固定 Provider の組織リソースは初期作成にも更新 API を使います。Access が未有効なアカウントでは、一度だけ管理 API で組織を初期化し、返された `auth_domain` を非公開の入力値へ保存してから適用します。組織の有効化後は同じリソースが既存組織の設定を管理します。
