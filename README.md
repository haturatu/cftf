# Cloudflare の Terraform 管理

cftf は、Cloudflare の Zone、DNS、WAF、Bot 対策、R2、Workers などの設定を Terraform で管理するための公開リポジトリです。**Terraform のコードと実際の設定値を分離する**ことを前提としています。

- Terraform の定義と非機密の検証処理は、このリポジトリで管理します。
- Zone 名、Zone / Account ID、DNS レコード、認証情報、Worker のソースなどの実値は、非公開 R2 の **Config バケット**に保管します。
- Terraform state は、Config とは別の非公開 **State バケット**に保管します。
- 本番の plan / apply と、その結果の詳細な検査は非公開のデプロイリポジトリで実行します。公開側に plan 本文や実リソースの情報は返しません。

公開のコードだけで本番環境を再構成できる仕組みではありません。非公開の設定、既存 state、バックアップ、実行権限が揃って初めて運用できます。

**重要:** Terraform の `sensitive` は通常の CLI 表示を抑制するための指定であり、機密情報を暗号化して隠す機能ではありません。`terraform.tfstate`、保存済み `tfplan`、`terraform show -json` の結果、Provider のデバッグログは公開しないでください。

## はじめに

### ディレクトリ構成

```text
cftf/
├── .github/workflows/         # 非機密の検証と private apply の要求
├── .github/scripts/           # PR の承認・マージ制御
├── stacks/
│   ├── zone/                 # 全 Zone 共通の Terraform root
│   ├── security-account/     # Account 共通の IP List / Turnstile
│   ├── r2/                   # R2 バケットと設定
│   ├── workers/              # 汎用 Workers の配備構成
│   └── f2b/                  # Fail2ban API のインフラ基盤
├── modules/
│   ├── zone/                 # Zone ごとの DNS、WAF、Bot、TLS など
│   └── account-security/     # Account 単位のセキュリティ設定
├── bootstrap/backend/        # State / Config バケットの作成と復旧
├── examples/                 # プレースホルダーを使った入力例
├── scripts/tf.sh             # Private 実行処理のローカル入口
└── .private/                 # Git 管理外の一時データ・詳細ログ
```

各 Zone に個別の Terraform ディレクトリを作るのではなく、`stacks/zone` を複数の匿名ターゲットから利用します。`zone-001` のような名前は実際のドメインや Cloudflare ID と無関係な識別子です。Private 側の許可リストが、使用できるターゲットと state キーを決定します。

同じ root を使っても、`TF_DATA_DIR` と backend の state キーをターゲットごとに分離します。**同じ State を異なるターゲットで共有しないでください。**

| 管理対象 | Terraform root | 役割 |
| --- | --- | --- |
| DNS、Zone 設定、WAF、Bot 対策 | `stacks/zone` | Zone ごとに独立した state |
| IP List、Turnstile | `stacks/security-account` | Account で共通の state |
| R2 バケット・設定 | `stacks/r2` | 既存バケットの管理 |
| 汎用 Workers | `stacks/workers` | スクリプト、Cron、Route、Domain 等 |
| Fail2ban API | `stacks/f2b` | D1、Access、カスタムドメイン等の箱 |
| State / Config バケット | `bootstrap/backend` | 初期作成・復旧専用 |

Zone モジュールの入力と制約は[Zone モジュール](modules/zone/README.md)、Account 共通の設定は[Account Security モジュール](modules/account-security/README.md)を参照してください。

### 変更前の確認

既存の Cloudflare 資源を取り込んで使う構成です。新規のターゲットや設定を追加する前に、次の点を確認してください。

1. 対象 Zone / Account が Private の許可リストに登録されており、正しい既存 state キーが割り当てられていること。
2. Config リビジョンが固定され、manifest と各ファイルの SHA-256 が一致すること。
3. 既存リソースの ID を非公開入力へ設定し、必要な `import` 定義が有効であること。
4. 同一の Cloudflare リソースや Ruleset Phase を、別の Terraform state が所有していないこと。
5. 非公開環境の plan が、意図しない削除・置換・設定の無効化を含まないこと。

**注意:** `terraform init -reconfigure` は backend の設定を再初期化する操作であり、state を移行する操作ではありません。誤った state キーや空の state を使った plan を、そのまま apply しないでください。

### ローカルでの検証

Arch Linux / Artix Linux でのパッケージ導入例です。

```sh
sudo pacman -S --needed \
  bash coreutils git github-cli jq terraform python python-pip aws-cli
```

CI は Terraform **1.15.9** を使用します。ローカルも同じバージョンに揃えてください。`github-cli` は `gh` コマンドのパッケージ名です。

インフラ認証情報なしで、公開側のフォーマット・入力値の検証・モックテストを実行できます。

```sh
terraform fmt -check -recursive
.github/scripts/control.test.sh
./scripts/tf.test.sh

terraform -chdir=modules/zone init -backend=false -input=false
terraform -chdir=modules/zone test

terraform -chdir=modules/account-security init -backend=false -input=false
terraform -chdir=modules/account-security test
```

この検証には Terraform Provider の取得などでネットワーク接続が必要になる場合がありますが、Cloudflare の本番認証情報は使用しません。テストに合格しただけでは、Cloudflare API への apply や権限の検証が完了したことにはなりません。

CI 相当の追加チェックは[テストと CI](#テストと-ci)を参照してください。

## 設定を plan / apply する

### Private 環境の準備

このリポジトリ単体から直接本番の plan を実行しません。隣接する非公開の `cftf-deploy` checkout、その仮想環境、Cloudflare / R2 の権限が必要です。

例の `.env.example` は変数名の参考です。実際の認証情報と承認済みの Config リビジョンを **Git 管理外**の `.env` に設定してください。値や内容をチャット、Issue、PR、CI のログに貼り付けないでください。

```sh
umask 077
set -a
. ./.env
set +a
```

既存の `.env` は上書きしないでください。Private リポジトリが標準の隣接ディレクトリにない場合は `CFTF_DEPLOY_DIR`、仮想環境の Python が異なる場合は `CFTF_DEPLOY_PYTHON` を設定します。

`scripts/tf.sh` は自分で Terraform plan の内容を表示・解析するスクリプトではありません。Private 側の `deployment.local` を呼び出す薄いラッパーです。R2 からの取得、実際の backend 設定、`TF_DATA_DIR` の分離、plan の検査、保存済み plan の apply は Private 側で処理します。

### 対象を確認する

```sh
./scripts/tf.sh --list-targets
```

出力されるのは、Private の `deployment/config.json` に登録された匿名ターゲット名だけです。リストを公開する設計であっても、ドメイン名・実 ID・state キーをターゲット名に埋め込まないでください。

Bash の補完が必要な場合は、リポジトリのルートから実行します。

```sh
source ./scripts/tf-completion.bash
```

永続化する場合は、この補完スクリプトを**絶対パス**で読み込む行を `~/.bashrc` に追加します。補完候補は Private の許可リストから取得され、設定の更新後も反映されます。

### plan を実行する

```sh
./scripts/tf.sh zone-001 plan
./scripts/tf.sh r2 plan
./scripts/tf.sh workers plan
./scripts/tf.sh security-account plan
```

`zone-001` などは例です。許可リストに存在する値だけを指定できます。

plan の通常の標準出力には、固定された状態メッセージだけを表示します。詳細は `.private/runtime/` に格納され、ディレクトリを `700`、ファイルを `600` として管理します。保存した plan や診断ログを公開しないでください。

### apply を実行する

```sh
./scripts/tf.sh zone-001 apply
```

`apply` は、Private 側で plan を生成・検査し、**検査した保存済み plan** を適用する操作です。通常の任意 Terraform オプションは受け付けません。実行には Private 側の権限と事前確認が必要です。

**警告:** `apply` を試すために実際の Zone を新規ターゲットへ割り当てたり、別の state キーへ切り替えたりしないでください。既存資源の削除・更新を引き起こす可能性があります。

## GitHub Actions からの反映

公開リポジトリの PR に `terraform-apply` ラベルを付けると、条件が揃った場合に承認・マージ・Private デプロイの要求が進みます。

1. `Terraform checks` がフォーマット、Terraform の構文・入力検証、モックテストを実行します。ここでは本番の Cloudflare 認証情報を使用しません。
2. 許可された利用者が `terraform-apply` ラベルを付けます。承認の対象は、その時点の PR head SHA です。
3. CI とレビュー状態を確認した controller が squash merge を行います。head が変わった場合は、古い承認・ラベルをそのまま利用できません。
4. controller はマージされた確定 SHA を非公開 `cftf-deploy` へ通知します。
5. Private CI が最新の `master`、承認、マージ SHA と R2 の固定設定リビジョンを確認し、全ターゲットの plan を検査します。
6. 意図しない削除・置換を拒否し、保存済み plan を適用します。

公開側へ返すのは固定の成功・失敗・後続コミットによる置き換え通知のみです。**plan の本文、ドメイン、ID、リソースの種類・件数は公開しません。** Private CI も PR ブランチのコードではなく、マージ済みコミットを対象にします。

`AUTOMATION_ENABLED` と Private 側の `DEPLOY_ENABLED` は初期状態では `false` です。運用開始には GitHub App、必要な Secrets、R2 の復旧、Private の設定と承認が必要です。

`terraform-apply` を付けないドキュメント PR は、通常の検証・レビュー対象です。ラベルを貼る場合は、条件が満たされると自動マージとデプロイ要求につながることに注意してください。実際のラベル処理は [request-apply.yml](.github/workflows/request-apply.yml) と [control.py](.github/scripts/control.py) を参照してください。

## R2 の設定と state

### Config リビジョン

非公開の Config バケットでは、一度承認した設定を上書きせず、`revisions/<revision>/` に新しいリビジョンとして保管します。

```text
revisions/<revision>/
├── backend.hcl
├── zones/<anonymous-target>.tfvars.json
├── security-account.tfvars.json
├── r2.tfvars.json
├── workers.tfvars.json
├── workers/...
└── manifest.json
```

`backend.hcl` には S3 互換のエンドポイントとバケット設定を記録しますが、**state キーは含めません**。state キーは Private の許可リストから取得します。

`*.tfvars.json` は Terraform 標準の JSON 入力形式です。複合した Cloudflare 設定は `value_json`、Ruleset のルール配列は `rules_json` に JSON 文字列として指定します。Worker の `source_path` などは、Private 側で取得した実ファイルの絶対パスへ変換します。

`manifest.json` 自体の SHA-256 に加え、manifest に含まれる各ファイルのサイズと SHA-256 も検証します。リビジョンの上書きは行わず、変更のたびに新たなリビジョンを発行します。

認証の権限は分離します。

| 認証 | 必要な用途 |
| --- | --- |
| Config 用 R2 キー | 承認済み設定を読み取る |
| State 用 R2 キー | 対象 state の読み書き |
| Cloudflare API token | Provider が管理資源を参照・更新する |
| GitHub App の認証 | Private デプロイ workflow を要求する |

このうちどれも公開リポジトリに保存しません。実値は Private 側の適切な Secrets / 環境変数で管理してください。

### state の注意点

Config と State の R2 バケットは分けます。両バケットとも公開アクセスを無効にし、管理者権限を必要最小限に制限してください。

R2 の S3 互換 API には S3 のオブジェクトバージョニングと同等の復旧機能がありません。state、bootstrap 情報、復旧に必要な認証情報のバックアップは、**別の非公開ストレージ**にも保管してください。

`bootstrap/backend` は日常の CI の apply 対象ではなく、State / Config バケットの初期作成と復旧専用です。既存 state とバケットを二重作成しないでください。

## Cloudflare Free プランの保護機能

以下は、このリポジトリで扱う Free プラン向け保護機能です。**機能の提供範囲**と、**このリポジトリでの実装・管理の有無**は別です。Cloudflare の制限や API の権限は変更されるため、適用時には公式ドキュメントと非公開環境の plan を確認してください。

### 機能一覧

| 機能 | Free プランの範囲 | cftf での管理 |
| --- | --- | --- |
| Cloudflare Free Managed Ruleset | 自動適用 | 原則そのまま使用。調整時は `managed_entrypoints` |
| HTTP / L3・L4 DDoS Protection | 自動防御 | 原則そのまま使用。L7 調整時は `managed_entrypoints` |
| WAF Custom Rules | Zone ごとに最大 5 ルール | `rulesets`（`http_request_firewall_custom`） |
| WAF Rate Limiting | Zone ごとに 1 ルール、10 秒単位 | `rulesets`（`http_ratelimit`） |
| IP Access Rules | Account 単位の API 上限あり | `access_rules` |
| IP Custom Lists | Account ごとに 1 リスト | `stacks/security-account` |
| User Agent Blocking | Zone ごとに最大 10 ルール | `user_agent_blocking_rules` |
| Leaked Credentials Detection | 漏洩資格情報の検出 | `leaked_credential_check` |
| Bot Fight Mode | Zone 全体へのチャレンジ | `bot_management.fight_mode` |
| Block AI Bots / AI Labyrinth | AI クローラー対策 | `bot_management` |
| Managed robots.txt | AI ポリシーの提示 | `bot_management` |
| Turnstile | Account ごとに最大 20 ウィジェット | `stacks/security-account` |
| URL Normalization | 許可された Zone で利用 | `url_normalization` |
| DNSSEC | Cloudflare 側で有効化可能 | `dnssec` |
| Managed Transforms | セキュリティヘッダー等 | `managed_transforms` |
| Authenticated Origin Pulls | オリジン向け mTLS | `authenticated_origin_pulls` |
| Browser Integrity Check | HTTP ヘッダー等の検査 | `settings` |
| Security Level / Under Attack | 緊急時のチャレンジ | `settings` |
| TLS 設定、HTTPS リダイレクト | Zone 設定 | `settings` |
| Hotlink、Email Obfuscation 等 | Zone 設定 | `settings` |
| Transform / Configuration / Cache Rules | プランごとのルール数制限 | `rulesets` |
| Security Analytics / Events | ダッシュボード・ログの表示 | Terraform 管理対象外 |
| Cloudflare Access / Tunnel | 無料枠あり | 対象構成の stack で管理 |

**注意:** Pro / Business / Enterprise 固有のルールやスコアを Free の条件式に追加しないでください。たとえば Bot Management の ML スコアは Free で利用できません。

プランの制限は [Cloudflare WAF](https://developers.cloudflare.com/waf/)、[Custom Rules](https://developers.cloudflare.com/waf/custom-rules/)、[Rate Limiting](https://developers.cloudflare.com/waf/rate-limiting-rules/)、[Bot Fight Mode](https://developers.cloudflare.com/bots/get-started/bot-fight-mode/)、[Turnstile](https://developers.cloudflare.com/turnstile/plans/)で確認できます。

### Web サイトのベースライン

ブラウザーから利用するサイトでは、`stacks/zone` の `web_baseline` を使用して基本的な Zone 設定をまとめて管理できます。以下は **非公開の Zone tfvars に追加する設定部分の例**です。

```json
{
  "web_baseline": {
    "url_normalization": false,
    "dnssec": false
  }
}
```

上記は完全な tfvars ファイルではありません。Zone ID、Account ID などの必須入力を含む全体例は [examples/zone.tfvars.json.example](examples/zone.tfvars.json.example) を参照してください。

`web_baseline` を指定した場合に管理する設定は次のとおりです。

| Zone 設定 | 値 |
| --- | --- |
| `ssl` | `strict`（Full (strict)） |
| `always_use_https` | `on` |
| `min_tls_version` | `1.2` |
| `tls_1_3` | `on` |
| `browser_check` | `on` |

既存の `settings` に同じ `setting_id` が含まれる場合はベースライン値を優先します。既存の Terraform リソースアドレスに影響しないよう、既存のマップキーがある場合はそれを再利用します。

`url_normalization = true` は、API と権限が対象 Zone で利用可能な場合だけ設定してください。Cloudflare API では plan に Zone の `Sanitize Read`、apply に `Sanitize Write` が必要です。`Zone Transform Rules` や `Zone WAF` の権限とは別です。

`dnssec = true` は Cloudflare 側の有効化を行いますが、これだけでは信頼チェーンが完成しません。レジストラへ DS レコードを登録し、`dig +dnssec` などで確認してください。

**保護対象の条件:** HTTP WAF が保護するのは Cloudflare を Proxy 経由で通るリクエストです。DNS レコードが DNS Only の場合は Cloudflare の HTTP WAF を通りません。

### WAF Custom Rules

`rulesets` にはユーザーが所有する Zone ルールセットを指定します。既存のルールセットを使う場合は、その **Zone エントリーポイントの ID** を `id` に指定して import します。未設定なら新規作成を試みます。

次は **モジュールの設定方法を示す HCL の例**です。`rulesets` の内容を Private の JSON tfvars で表現する場合は、`rules_json` を JSON 文字列として格納します。

```hcl
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
      }
    ])
  }
}
```

Free プランでは Custom Rules が 5 件までです。既存の Cloudflare Dashboard で管理しているルールと Terraform 側のルールを別々に数えず、**その Phase 全体の上限**として確認してください。

### Rate Limiting

Rate Limiting は `http_ratelimit` Phase に設定します。Free プランでは 1 Zone あたり 1 ルール、計測区間は 10 秒です。`characteristics` に `cf.colo.id` を含めます。

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

`requests_per_period = 30` は設定例であり、推奨値ではありません。通常の利用者やモバイルクライアントのアクセス量に合わせて調整してください。

`block` の期間指定には `mitigation_timeout = 10`、`challenge` / `js_challenge` / `managed_challenge` の request throttling には `mitigation_timeout = 0` を使用します。Free / Pro / Business の challenge は期間指定と挙動が異なります。

Rate Limiting は各 Cloudflare データセンターで計数されるため、世界全体のリクエストを合計した固定上限ではありません。詳しくは [Rate Limiting の制限](https://developers.cloudflare.com/waf/rate-limiting-rules/troubleshooting/) を参照してください。

### Bot 対策と Turnstile

`bot_management.fight_mode` はブラウザー中心の Zone で検討してください。**Bot Fight Mode は Zone 全体に作用し、WAF Custom Rules の Skip では除外できません。** API、モバイルアプリ、ヘルスチェックの通信がチャレンジされる可能性があります。

API を提供する Zone では、まず WAF、必要な範囲の Rate Limiting、Cloudflare Access を組み合わせる方が制御しやすい場合があります。

`bot_management` には AI クローラー対策の `ai_bots_protection`、`crawler_protection`、`is_robots_txt_managed`、`ai_training`、`ai_user`、`aisearch`、`cf_robots_variant`、`bot_preference_sync_enabled` などを指定できます。実際に利用できる値は [modules/zone/variables.tf](modules/zone/variables.tf) の validation と対象 Zone の API に従ってください。

Turnstile は、ページ全体に Bot Fight Mode を適用せず、ログイン・登録・フォーム送信など特定の処理を保護したい場合に利用できます。サイト側で発行したトークンを検証する実装が必要です。Widget の作成だけでフォーム送信の検証が完了するわけではありません。

### TLS、ヘッダー、オリジン

Zone の TLS とブラウザー保護は `settings` で管理します。

| `setting_id` | 設定値の例 | 目的 |
| --- | --- | --- |
| `ssl` | `strict` | Full (strict) |
| `always_use_https` | `on` | HTTPS へリダイレクト |
| `automatic_https_rewrites` | `on` | 一部の混在コンテンツを HTTPS に書き換え |
| `min_tls_version` | `1.2` | 最小 TLS バージョン |
| `tls_1_3` | `on` | TLS 1.3 |
| `security_header` | HSTS の JSON 値 | ブラウザーの HTTPS 強制 |
| `browser_check` | `on` | Browser Integrity Check |
| `security_level` | `medium` | `under_attack` は緊急時のみ |
| `email_obfuscation` | `on` | メールアドレスの収集抑制 |
| `hotlink_protection` | `on` | 画像の直リンク制限 |
| `replace_insecure_js` | `on` | 危険なライブラリの置換 |

`settings.value_json` には JSON で表現した設定値を指定します。

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

**警告:** HSTS の `include_subdomains` / `preload` は、すべての対象ホストが HTTPS に対応し、長期間維持できることを確認してから有効にしてください。設定を誤るとブラウザーからのアクセスを長期間妨げます。

`managed_transforms` の `add_security_headers` はセキュリティヘッダーを追加します。CSP などサイト固有の応答ヘッダーには `http_response_headers_transform` Phase を使用できます。

Authenticated Origin Pulls は Cloudflare からオリジンへの認証に使用しますが、**オリジン側にも証明書と検証設定が必要**です。Cloudflare 側で有効化しただけで保護は完成しません。

### Free Managed Ruleset と既存 Phase

Free Managed Ruleset および HTTP DDoS Protection は、通常 Cloudflare が自動で適用します。**自動適用される既存ルールセットを Terraform で新規作成し直さないでください。**

既存 Phase の挙動を調整する場合は `managed_entrypoints` を使用します。対象は Cloudflare が実行する管理ルールセット本体（`kind = "managed"`）ではなく、Zone の Phase エントリーポイント（`kind = "zone"`）です。

- `id` は **Zone エントリーポイント Ruleset** の ID を指定します。
- `rules_json` は管理ルールセット ID を `action_parameters.id` に持つ、有効な `execute` ルールを含めます。
- 空の `rules_json` や無条件の `skip` は、保護機能が失われるおそれがあるためモジュールで拒否します。
- 既存 Phase がある場合は import し、**無変更の plan** を確認してから修正します。

管理 Ruleset の実 ID は Cloudflare API の rulesets 一覧から取得してください。実行先 Zone で使える管理ルールセットかどうかを確認し、例示された ID を無条件に流用しないでください。

### 同じ Phase の所有権を分離する

Cloudflare では、同じ Zone / Phase のエントリーポイントを複数の Terraform state から管理しないでください。

`stacks/f2b` は、対象 Zone の `http_request_firewall_custom` Phase を所有し、API クライアントに対する Browser Integrity Check の Skip を設定します。同じ Zone を `stacks/zone` でも管理する場合は、この Phase を重複して追加しないでください。

所有権を移す場合の順序:

1. 両 stack の自動 apply を停止します。
2. 対象ルールセットの ID と現在のルールを API / state から取得し、非公開で保存します。
3. 旧 `stacks/f2b` 側で `manage_api_browser_check = false` とし、Private 環境で `terraform state rm 'cloudflare_ruleset.api_browser_checks[0]'` を実行して、**実体を削除せずに state からのみ除外**します。
4. 新 `stacks/zone` に既存ルールセット ID と全ルールを非公開入力として設定し、import します。
5. plan が無変更であることを確認してから、実行を再開します。

`stacks/zone` は `cloudflare_rulesets` データソースで既存 Zone Phase を確認し、新規作成時の重複を拒否します。ただし、**別の state が所有しているかどうかまでは自動判定できません。** 移管中は適用処理を停止してください。

### Free プランの対象外

Super Bot Fight Mode、Bot Management の ML スコア、Cloudflare Managed Ruleset のフル版、OWASP Core Ruleset、Advanced Rate Limiting、Managed IP Lists、Enterprise の Account-level WAF、Sensitive Data Detection などは、Free プランの利用対象外です。`matches` など一部の式演算子にもプラン制限があります。

Free プラン用の設定に有料機能を混在させないでください。該当する機能は、Cloudflare 側の API で拒否される場合があります。

## Account 共通のセキュリティ

IP Custom List と Turnstile は Zone 単位ではなく Account 単位の資源です。`stacks/security-account` にまとめて管理し、複数の Zone state から同じリストや Widget を作成しないでください。

- **IP List:** Free では最大 1 リスト、10,000 項目。IPv4 / IPv6 / CIDR を指定します。
- **Turnstile:** Free では最大 20 Widget。ログイン・フォーム用途などで使用します。
- **既存資源の取り込み:** IP List の `import_id` はリスト ID、Turnstile の `import_id` は sitekey です。
- **IP List の既存項目:** `items` を省略すると項目を保持し、空配列を明示すると全項目を削除します。

**注意:** Turnstile の secret は Terraform state に保存されます。`sensitive` 指定があっても state を公開しないでください。詳しい入力条件と例は [Account Security モジュール](modules/account-security/README.md)を参照してください。

## Fail2ban API の管理範囲

`stacks/f2b` は、D1、Cloudflare Access の組織 / Service Token / 収集ポリシー、カスタムドメイン、WAF など、アプリケーションを配備するための**インフラ基盤**を管理します。

**Worker のソースコード・バージョン・バインディングをこの stack からデプロイしません。** アプリケーションは別の [f2b-api](https://github.com/haturatu/f2b-api) リポジトリが Wrangler を使って配備します。D1 のマイグレーションも `f2b-api/migrations` を使用します。

非公開の `terraform output -json deployment_config` の内容は、`f2b-api` の保護された `production` 環境にある `F2B_DEPLOY_CONFIG` Secret へ設定します。出力には D1 ID、Worker 名、Access の AUD と設定が含まれるため、公開ログや PR コメントに貼り付けないでください。

収集ドメインは Access の Service Auth で保護し、収集元ごとに Service Token を発行します。Worker の `workers.dev` とプレビュー URL は Wrangler 側で無効化します。`stacks/f2b` が所有する WAF Phase を `stacks/zone` でも重複管理しないでください。

Access の組織が未作成の場合は、初回だけ管理 API による組織の初期化が必要となる構成があります。`auth_domain` を非公開入力へ保存してから plan してください。

## テストと CI

CI の `Terraform checks` は、Cloudflare の本番認証情報を使わずに次の確認を行います。

- `terraform fmt -check -recursive`
- PR 承認 controller とローカルラッパーのテスト
- 各 stack / bootstrap の `terraform init -backend=false` と `validate`
- Zone、Account Security、bootstrap、f2b などの `terraform test`

ローカルでシェルの静的解析と workflow の検証を行うには、`shellcheck`、`shfmt`、`actionlint` を追加します。

```sh
sudo pacman -S --needed shellcheck shfmt actionlint

shellcheck -x scripts/*.sh scripts/*.bash .github/scripts/*.sh
shfmt -d -i 2 -ci -sr scripts/*.sh scripts/*.bash .github/scripts/*.sh
actionlint -ignore 'unexpected key "queue" for "concurrency" section' \
  .github/workflows/*.yml
```

現行 CI が使用する `concurrency.queue: max` は、actionlint 1.7.12 で未認識となるため、その警告だけを除外します。

Terraform Provider は stack ごとの `.terraform.lock.hcl` で固定します。Provider 更新時は Private 側の `deployment/config.json` の `provider_version` と `trust/cloudflare.lock.hcl` を揃えてください。Terraform CLI のバージョンも公開・Private の workflow 間で一致させます。

`imports.tf` は既存リソースを初めて state に取り込むための定義です。対象の import と plan の一致を確認する前に削除しないでください。

R2 の一部設定（Managed Domain、Lifecycle、CORS）は固定 Provider で import に未対応です。初回 plan で作成として表示されても、既存の設定を上書きする API 呼び出しとなる場合があります。必ず非公開環境で差分と意図を確認してください。

[Dependabot の設定](.github/dependabot.yml)は、GitHub Actions と Terraform Provider の定期更新を管理します。自動更新 PR も通常のレビュー対象であり、`terraform-apply` ラベルなしに本番反映されるわけではありません。

## 参考資料

- [Cloudflare Terraform の R2 backend](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Cloudflare WAF とプラン別の機能](https://developers.cloudflare.com/waf/)
- [Cloudflare Rate Limiting](https://developers.cloudflare.com/waf/rate-limiting-rules/)
- [Bot Fight Mode](https://developers.cloudflare.com/bots/get-started/bot-fight-mode/)
- [Terraform の設計ガイドライン](https://future-architect.github.io/arch-guidelines/documents/forTerraform/terraform_guidelines.html)
- [GitHub Actions のイベント](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
