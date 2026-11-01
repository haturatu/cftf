# cftf

Cloudflare の DNS、WAF、Bot 対策、R2、Workers などを Terraform で管理するためのリポジトリです。

Cloudflare のダッシュボードで設定するのも悪くないのですが、Zone が増えてくると「何をどこで変更したのか」が分かりづらくなります。同じ設定を複数の Zone に入れるのも面倒です。

なので、まとめて Terraform で管理することにしました。

ただ、普通に Terraform を書くとドメイン名や Zone ID がそのままコードに出てきます。それでは公開リポジトリにしづらいですし、設定ファイルを全部ローカルに置くのも端末への依存が増えてしまいます。

結果的に、**コードは GitHub、実際の設定値は非公開の R2、plan / apply は Private リポジトリ**という構成にしています。

| 置き場所 | 何を置くか |
| --- | --- |
| 公開の `cftf` | Terraform のコード、モジュール、認証情報不要のテスト |
| 非公開 R2 の Config バケット | Zone ID、DNS、WAF、Worker ソースなどの設定値 |
| 非公開 R2 の State バケット | Terraform state |
| 非公開の `cftf-deploy` | 設定の取得、plan の検査、承認後の apply |

公開リポジトリを clone するだけで本番構成を復元できるわけではありません。R2 の設定・state・権限・バックアップがそろって初めて動きます。

ここで勘違いしやすいのが Terraform の `sensitive` です。これは通常の出力を隠すための指定であって、値を暗号化するわけではありません。**state、保存した plan、`terraform show -json`、Provider のデバッグログは公開しないでください。**

## ディレクトリ構成

```text
cftf/
├── .github/
│   ├── workflows/         # 公開側のテストとデプロイ要求
│   └── scripts/           # PR の承認・マージ処理
├── stacks/
│   ├── zone/              # Zone 共通の Terraform root
│   ├── security-account/  # Account 単位の IP List と Turnstile
│   ├── r2/                # R2 バケットと各種設定
│   ├── workers/           # 汎用 Workers
│   └── f2b/               # Fail2ban API のインフラ
├── modules/
│   ├── zone/
│   └── account-security/
├── bootstrap/backend/     # State / Config バケットの初期構築・復旧
├── examples/              # ダミー値を使った設定例
└── scripts/tf.sh          # Private 側の実行処理を呼び出す
```

`stacks/` が Terraform を実行する単位で、`modules/` は共通化したリソース定義です。

### Zone ごとにコードを複製しない

例えば 10 個の Zone を持っているとして、Zone ごとにほぼ同じ Terraform ファイルを作ると、WAF の変更のたびに 10 回修正することになります。

それを避けるため、`stacks/zone` という共通 root を使い、設定値だけを切り替えます。

`zone-001` や `zone-002` といった匿名ターゲットから実際の Zone への対応は、Private 側の許可リストで管理します。コードにドメインや Zone ID を書く必要はありません。

ただし、同じ root を使うからといって state まで共有するわけではありません。ターゲットごとに `TF_DATA_DIR` と backend の state キーを分けています。**別々の Zone に同じ state キーを設定しないようにしてください。**

| Stack | 管理範囲 |
| --- | --- |
| `stacks/zone` | DNS、WAF、Bot、TLS、DNSSEC |
| `stacks/security-account` | Account 共通の IP List と Turnstile |
| `stacks/r2` | R2 のバケット、公開設定、Lifecycle、CORS |
| `stacks/workers` | 汎用 Worker のスクリプト、Cron、Route、カスタムドメイン |
| `stacks/f2b` | Fail2ban API 用の D1、Access、WAF など |
| `bootstrap/backend` | State / Config バケットの初期作成と復旧 |

モジュールの詳しい入力は [Zone](modules/zone/README.md) と [Account Security](modules/account-security/README.md) に書いています。

## テストする

いきなり本番の Cloudflare に接続するのではなく、まず公開側のテストを実行します。これらは Cloudflare の本番認証情報を必要としません。

Arch Linux / Artix Linux で必要なパッケージを入れる場合は、例えば以下です。

```sh
sudo pacman -S --needed \
  bash coreutils git github-cli jq terraform python python-pip aws-cli
```

CI の Terraform は `1.15.9` です。バージョンが違うと Provider や構文の影響で別の問題が出るので、できればそろえてください。

```sh
terraform fmt -check -recursive

# PR の承認処理と実行ラッパー
.github/scripts/control.test.sh
./scripts/tf.test.sh

# Terraform モジュールのテスト
terraform -chdir=modules/zone init -backend=false -input=false
terraform -chdir=modules/zone test

terraform -chdir=modules/account-security init -backend=false -input=false
terraform -chdir=modules/account-security test
```

`-backend=false` にしているのは、本番 state に接続しないためです。Provider の取得でネットワークが必要になることはありますが、ここで Cloudflare の設定が変更されるわけではありません。

各 stack の `validate` や追加テストも CI で実行しています。シェルや Workflow の検査は後述します。

## plan と apply

### なぜ Private 側で実行するのか

非公開の tfvars を使えば安全かというと、そうでもありません。Terraform は plan にリソース名や識別子を出しますし、`terraform show -json` ならさらに多くの値を取得できます。

そのため、公開側では本番の plan / apply を実行しません。

`scripts/tf.sh` は Terraform を直接実行するものではなく、Private の `deployment.local` を呼び出すだけのラッパーです。R2 からの取得、state の選択、plan の保存、削除・置換の検査は Private 側で行います。

### 準備

標準では、リポジトリを次のように並べて使います。

```text
~/git/
├── cftf/
└── cftf-deploy/  # 非公開
```

違う場所に配置する場合は `CFTF_DEPLOY_DIR` を指定できます。Private 側の Python 仮想環境が別の場所にある場合は `CFTF_DEPLOY_PYTHON` を指定してください。

`.env.example` を参考に、Cloudflare と R2 の認証情報、承認した Config リビジョンを Git 管理外の `.env` に設定します。既存のファイルを上書きしないようにしてください。

```sh
umask 077
set -a
. ./.env
set +a
```

`umask 077` だけで既存ファイルの権限まで変わるわけではありません。`.env` 自体の権限も確認が必要です。

### 対象の確認

```sh
./scripts/tf.sh --list-targets
```

Private の `deployment/config.json` にある匿名ターゲットが表示されます。実際のドメインや state キーが見えるものではありません。

Bash で補完したい場合は、以下を読み込めます。

```sh
source ./scripts/tf-completion.bash
```

毎回使うなら、絶対パスに直して `~/.bashrc` に追加してください。候補はそのときの Private 側の許可リストから取得します。

### plan の実行

```sh
./scripts/tf.sh zone-001 plan
./scripts/tf.sh r2 plan
./scripts/tf.sh workers plan
./scripts/tf.sh security-account plan
```

`zone-001` は例なので、実際には `--list-targets` に出る名前を使ってください。

通常の出力は固定の状態メッセージだけです。実際の差分や診断ログは Git 管理外の `.private/runtime/` に保管し、ディレクトリ `700`、ファイル `600` の権限で扱います。

### apply の実行

```sh
./scripts/tf.sh zone-001 apply
```

Private 側で plan を作り直し、検査した**保存済み plan** を適用します。公開側から任意の Terraform オプションを渡せるようにはしていません。

既存の環境で特に気を付けたいのが state キーです。`terraform init -reconfigure` は backend を再設定するだけで、state の移行は行いません。間違ったキーで空の state を見てしまうと、すでに存在するリソースを新しく作ろうとする場合があります。

通常の本番反映は、次の「GitHub Actions で反映する」にある PR ラベル経由の CI/CD を使用します。ローカルの `apply` は復旧・緊急時だけに限定し、通常はローカルで `plan` の内容を確認してから CI/CD の apply を実行してください。

**警告:** `apply` を試すために実際の Zone を新規ターゲットへ割り当てたり、別の state キーへ切り替えたりしないでください。既存資源の削除・更新を引き起こす可能性があります。

**初回の取り込みや移管では、正しい state を見ているか、ほかの state が同じリソースを所有していないか、必ず plan で確認してください。**

## GitHub Actions で反映する

手動実行だけではなく、PR のレビューから Private 側の apply までつなげています。

1. PR を作ると `Terraform checks` が実行されます。公開側で機密情報は使いません。
2. 許可されたユーザーが `terraform-apply` ラベルを付けます。この時点の **head SHA** が承認対象です。
3. テストとレビュー状態を確認した controller が squash merge します。コミットが更新されたら、古い承認を引き継ぎません。
4. マージされた SHA を Private の `cftf-deploy` に通知します。
5. Private 側でもマージ済みコミットと R2 リビジョンを確認し、全ターゲットの plan を検査してから apply します。

公開側に返すのは固定の成功・失敗などの通知だけで、plan 本文やリソース名、件数、実際の ID は出しません。

以前は `AUTOMATION_ENABLED` と `DEPLOY_ENABLED` を使っていましたが、現在は**自動化が既定で有効**になる構成です。両方の有効化 PR をマージした後は、古い Enabled 変数を参照しません。

ただし、何でも自動で apply するわけではありません。GitHub App、Secrets、R2 の State / Config、固定した設定リビジョンを確認し、Private 側の `Private Terraform checks`（`verify.yml`）を現行 `master` で成功させてから `terraform-apply` ラベルを使ってください。許可された人のラベル操作、最新 head SHA、CI、レビュー、Private 側の plan 検査は引き続き必要です。

### 自動反映を緊急停止する

問題があれば、GitHub の Repository Variables で止められます。

```sh
# 公開側の自動マージ・デプロイ要求を停止
gh variable set AUTOMATION_DISABLED --repo haturatu/cftf --body true

# Private 側の apply を停止
gh variable set DEPLOY_DISABLED --repo haturatu/cftf-deploy --body true
```

復旧と検証が済んだら、それぞれ `false` に戻します。`AUTOMATION_DISABLED` は公開側の自動マージ・デプロイ要求、`DEPLOY_DISABLED` は Private 側の apply ジョブを止めます。Private の `verify.yml` は停止スイッチに関係なく手動の確認に使えます。

`terraform-apply` を付けると、条件が満たされた際に**自動マージとデプロイ要求**まで進みます。ドキュメントだけを変更する PR では、通常このラベルを付ける必要はありません。

実際の処理は [request-apply.yml](.github/workflows/request-apply.yml) と [control.py](.github/scripts/control.py) にあります。

## R2 に置く設定と state

### Config リビジョン

設定ファイルは、非公開の Config バケットに次のような単位で保存します。

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

`backend.hcl` には R2 の S3 互換エンドポイントやバケットの設定を入れますが、state キーは入れません。state キーは Private 側の許可リストで管理します。

tfvars は Terraform 標準の JSON 形式を使います。設定値の JSON は `value_json`、WAF のルール配列は `rules_json` です。Worker のソースパスも、Private 側でダウンロードした実ファイルの絶対パスへ変換します。

一度承認したリビジョンは上書きせず、変更時は新しく発行します。manifest の SHA-256 と、ファイルごとのサイズ・SHA-256 を確認してから使用するため、途中で内容が変わっていた場合は拒否する構成です。

### 認証情報も分ける

| 認証情報 | 用途 |
| --- | --- |
| Config 用 R2 キー | 設定の読み取り |
| State 用 R2 キー | 対象 state の読み書き |
| Cloudflare API token | 実際のリソースの確認と更新 |
| GitHub App | Private のデプロイ Workflow を要求 |

これらを公開 GitHub に置かないことはもちろん、**Config 読み取り用のキーで State まで操作できるようにしない**ことも重要です。

R2 の State と Config は別のバケットにしています。どちらも非公開です。

なお、R2 は S3 のオブジェクトバージョニングと同じ方法で state を復元できるものではありません。State、bootstrap の復旧情報、認証情報は、別の非公開ストレージにもバックアップしておく必要があります。

`bootstrap/backend` は初期作成と復旧のためのものです。普段の CI から毎回 apply する用途ではありません。

## Cloudflare Free のセキュリティ機能

このリポジトリは Free プランで使える機能を中心に作っています。

ただし、Cloudflare が自動で適用しているもの、Terraform で管理できるもの、ダッシュボードだけで見るものは別です。片っ端から Terraform のリソースを作れば防御が強くなるわけでもありません。

以下はこのリポジトリで扱っている主な機能です。プラン上限や API の権限は変わることがあるので、適用前には Cloudflare の公式ドキュメントと実際の plan を確認してください。

| 機能 | Free プランでの扱い | Terraform 側 |
| --- | --- | --- |
| Free Managed Ruleset | Cloudflare が自動適用 | 原則そのまま使う |
| HTTP DDoS Protection | 自動適用 | 上書きする場合のみ `managed_entrypoints` |
| WAF Custom Rules | 5 ルール / Zone | `rulesets` |
| WAF Rate Limiting | 1 ルール / Zone、10 秒 | `rulesets` |
| IP Access Rules | IP / ASN / 国など | `access_rules` |
| IP Custom List | 1 リスト / Account | `stacks/security-account` |
| User Agent Blocking | 10 ルール / Zone | `user_agent_blocking_rules` |
| Bot Fight Mode | Zone 全体に適用 | `bot_management.fight_mode` |
| Block AI Bots / AI Labyrinth | AI クローラー対策 | `bot_management` |
| Managed robots.txt | クローラー向けポリシー | `bot_management` |
| Leaked Credentials Detection | 漏洩資格情報の検出 | `leaked_credential_check` |
| Turnstile | 20 Widget / Account | `stacks/security-account` |
| URL Normalization | 利用できる Zone のみ | `url_normalization` |
| DNSSEC | レジストラ側の設定も必要 | `dnssec` |
| Managed Transforms | セキュリティヘッダーなど | `managed_transforms` |
| Authenticated Origin Pulls | オリジンでの検証が必要 | `authenticated_origin_pulls` |
| Browser Integrity Check | HTTP ヘッダーなどを検査 | `settings` |
| TLS / HTTPS / Security Level | Zone 設定 | `settings` |
| Configuration / Transform / Cache Rules | プランごとの上限あり | `rulesets` |
| Security Analytics / Events | ダッシュボードで確認 | 対象外 |
| Access / Tunnel | 無料枠あり | 対象の stack で管理 |

### Web サイトの基本設定

毎回 `ssl = strict` や HTTPS リダイレクトを手で指定するのも面倒なので、ブラウザー向けサイトには `web_baseline` を用意しています。

非公開の Zone tfvars に、例えば以下の設定を追加します。

```json
{
  "web_baseline": {
    "url_normalization": false,
    "dnssec": false
  }
}
```

これは設定の一部です。必須の Account / Zone 情報を含むファイル全体は [zone.tfvars.json.example](examples/zone.tfvars.json.example) を参照してください。

この設定で管理する値は次のとおりです。

| 設定 | 値 |
| --- | --- |
| `ssl` | `strict`（Full (strict)） |
| `always_use_https` | `on` |
| `min_tls_version` | `1.2` |
| `tls_1_3` | `on` |
| `browser_check` | `on` |

既存の `settings` と同じ `setting_id` がある場合は、このベースラインの値が優先されます。

`url_normalization = true` は、Cloudflare 側でその Zone が対応している場合だけ設定してください。API では Zone の `Sanitize Read` / `Sanitize Write` 権限が必要です。`dnssec = true` にした場合は、Cloudflare 側で有効にするだけでなく、レジストラへ DS レコードを登録する必要があります。

また、Cloudflare の HTTP WAF が効くのは、リクエストが Proxy を経由しているときだけです。DNS Only のレコードは HTTP WAF を通りません。

### WAF Custom Rules

例えば `/.env` や `/.git/` などへのアクセスを拒否する場合、`http_request_firewall_custom` にルールを追加します。

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

これはモジュール入力を HCL で表した例です。実際の R2 設定は JSON tfvars なので、`rules_json` を JSON 文字列として保存します。

Free の上限は Zone あたり 5 ルールです。既存ルールを別の Terraform state で管理していないかも確認してください。

### Rate Limiting

Rate Limiting は `http_ratelimit` Phase に設定します。Free プランでは 1 Zone あたり 1 ルール、計測区間は 10 秒です。`characteristics` は `cf.colo.id` と `ip.src` の組み合わせに固定します。この組み合わせは IP アドレスと Cloudflare データセンター単位でリクエストを数えるため、世界全体の固定上限ではありません。

全 HTTP 通信を対象にする基本形です。`expression = "true"` は、その Phase に到達するすべてのリクエストに適用されます。`action = "block"` は Cloudflare 標準の 429 応答を返します。Free プランでは `ratelimit.response` によるカスタム 429 本文を設定できないため、モジュールは指定を拒否します。

```hcl
rulesets = {
  global_rate_limit = {
    name        = "Global HTTP Rate Limit"
    description = "IP-based limit for all HTTP traffic"
    kind        = "zone"
    phase       = "http_ratelimit"
    rules_json = jsonencode([{
      ref         = "global_ip_rate_limit"
      description = "Limit all HTTP requests per IP"
      action      = "block"
      expression  = "true"
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

`requests_per_period = 30` は 10 秒あたり 30 リクエスト（平均 3 req/s）の開始値です。ブラウザーの並列取得、API 呼び出し、同じ IP から複数ホストへのアクセスを合算して、正規利用が上限を超えないか確認してください。

対象パスを限定する場合は `expression` を変更します。

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

`block` / `log` には `mitigation_timeout = 10`、`challenge` / `js_challenge` / `managed_challenge` の request throttling には `mitigation_timeout = 0` を使用します。Free / Pro / Business の challenge は期間指定と挙動が異なります。

Rate Limiting は各 Cloudflare データセンターで計数されるため、世界全体のリクエストを合計した固定上限ではありません。Free プランでは 1 ルールの制限と、過負荷時の fail-open があります。詳しくは [Rate Limiting の制限](https://developers.cloudflare.com/waf/rate-limiting-rules/troubleshooting/) を参照してください。

### Bot Fight Mode を全 Zone で有効にすればいいわけではない

Bot Fight Mode はブラウザーで見る Web サイトには便利ですが、API やモバイルアプリを提供する Zone では面倒なことがあります。正規のクライアントまでチャレンジされる場合があるためです。

しかも、**Bot Fight Mode は WAF Custom Rules の Skip で除外できません**。

なので API 用の Zone では、まず WAF、Rate Limiting、Cloudflare Access などを組み合わせる方が扱いやすい場合があります。

`bot_management` には Bot Fight Mode 以外にも、`ai_bots_protection`、`crawler_protection`、`is_robots_txt_managed`、`ai_training`、`ai_user`、`aisearch` などがあります。実際の入力値は [modules/zone/variables.tf](modules/zone/variables.tf) を確認してください。

フォームだけ保護したければ Turnstile も使えます。ただし Widget を作成するだけでは保護になりません。アプリケーション側で発行されたトークンを Siteverify で検証する必要があります。

### TLS とセキュリティヘッダー

TLS 周りは `settings` で管理します。主な値は以下です。

| `setting_id` | 例 | 用途 |
| --- | --- | --- |
| `ssl` | `strict` | Full (strict) |
| `always_use_https` | `on` | HTTPS リダイレクト |
| `automatic_https_rewrites` | `on` | 混在コンテンツの一部を書き換える |
| `min_tls_version` | `1.2` | TLS の最小バージョン |
| `tls_1_3` | `on` | TLS 1.3 |
| `security_header` | HSTS の JSON 設定 | HTTPS 接続の強制 |
| `browser_check` | `on` | Browser Integrity Check |
| `security_level` | `medium` | `under_attack` は緊急時向け |
| `hotlink_protection` | `on` | 画像の直リンク防止 |
| `email_obfuscation` | `on` | メールアドレスの難読化 |

`value_json` には JSON として有効な文字列を指定します。

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

HSTS は有効にすればいいというものでもありません。特に `include_subdomains` や `preload` は、ほかのサブドメインまで HTTPS を維持できると確認してから使ってください。

`managed_transforms` では `add_security_headers` のような既定の変換を使えます。CSP などサイト固有のヘッダーは `http_response_headers_transform` で設定できます。

また、Authenticated Origin Pulls を使うなら、オリジン側でもクライアント証明書を検証する必要があります。Cloudflare 側のスイッチだけで完了するものではありません。

### Managed Ruleset はむやみに上書きしない

Cloudflare Free Managed Ruleset と HTTP DDoS Protection は通常自動適用されるため、基本的に Terraform で作り直す必要はありません。

それでも既存の Phase の実行設定を変更したい場合は `managed_entrypoints` を使います。

ここで指定する `id` は、管理ルールセット本体の ID ではなく、**Zone の Phase エントリーポイント Ruleset ID** です。`rules_json` には有効な `execute` ルールと、その `action_parameters.id` に実際の管理 Ruleset ID を指定します。

空の配列などを渡して保護が消えないよう、モジュールでも入力を検証します。ただし全ての設定事故を防げるわけではないので、変更前に既存 Phase を import し、まず無変更の plan を確認してください。

### 同じ Ruleset を二つの state で管理しない

ちょっとややこしいのが `stacks/f2b` です。この stack は API 用に `http_request_firewall_custom` を所有しています。API クライアントに必要な Browser Integrity Check の Skip もここに入っています。

同じ Zone を `stacks/zone` でも管理するなら、その Phase を両方に作らないようにしてください。

どうしても所有権を移す場合は、次の順番にします。

1. 両 stack の自動 apply を止める。
2. 既存 Ruleset の ID と内容を Private 側で保存する。
3. 旧 `stacks/f2b` の `manage_api_browser_check` を `false` にし、`terraform state rm 'cloudflare_ruleset.api_browser_checks[0]'` で**実際の Ruleset は消さずに**旧 state から外す。
4. 新しい `stacks/zone` の非公開入力に同じ ID とルールを設定して import する。
5. 無変更の plan を確認してから apply を再開する。

`stacks/zone` はデータソースで同じ Phase の重複作成を検出しますが、**別 state の所有権までは分かりません**。移管している間は自動 apply を止めておくのが前提です。

### Rate Limiting の import と Phase の重複

`http_ratelimit` の Zone エントリーポイントが Cloudflare に既にある場合、`id` なしで追加すると重複作成になります。`stacks/zone` は `cloudflare_rulesets` データソースで既存 Phase を検出し、`id` がない `rulesets` エントリを plan 時に拒否します。

1. 対象 Zone の `http_ratelimit` Phase エントリーポイントを Cloudflare API または Dashboard で確認します。
2. 存在する場合は、その 32 文字の Ruleset ID を `rulesets.global_rate_limit.id` に指定し、現在のルールを `rules_json` にそのまま再現します。
3. 存在しない場合だけ `id` を省略して新規作成します。
4. 既存ルールを import した直後の plan が無変更であることを確認します。差分が出る場合は、`rules_json` が現在のルールと一致していません。
5. 同じ Zone の `http_ratelimit` を別の stack や state で同時に管理しないでください。`stacks/f2b` が所有するのは `http_request_firewall_custom` であり、`http_ratelimit` とは別 Phase です。

Provider の Ruleset import ID は `zones/<zone_id>/<ruleset_id>` です。`id` を指定した場合だけ `imports.tf` が import を適用します。

### Free で使えない機能

Super Bot Fight Mode、Bot Management の ML スコア、Cloudflare Managed Ruleset のフル版、OWASP Core Ruleset、Advanced Rate Limiting、Managed IP Lists、Enterprise の Account-level WAF などは Free プランの対象外です。

Terraform に値を書けば使えるようになるわけではありません。`matches` などの式にもプランによる制限があります。

## Account 単位のセキュリティ

IP Custom List と Turnstile は Zone ではなく Account に属します。Zone ごとの state にそれぞれ作ると二重管理になるため、`stacks/security-account` に分けました。

IP List は Free だと 1 Account につき 1 リスト、最大 10,000 項目です。Turnstile は最大 20 Widget です。

既存の IP List を import する場合、`items` を指定しないと現在のリスト内容を維持します。これに対して **`items = []` は全項目の削除**なので注意してください。

Turnstile の sitekey は公開値ですが、secret は Terraform state に入ります。詳しくは [Account Security モジュール](modules/account-security/README.md) にあります。

## f2b-api との役割分担

`stacks/f2b` は D1、Cloudflare Access、Service Token、カスタムドメイン、WAF といった、API を動かすための**土台**を作ります。

アプリケーションのソースを Terraform でデプロイするわけではありません。実際の Worker は別リポジトリの [f2b-api](https://github.com/haturatu/f2b-api) が Wrangler でデプロイし、D1 のマイグレーションもそちらで実行します。

Terraform の `deployment_config` 出力には D1 の ID や Access の設定などが含まれます。`terraform output -json deployment_config` は非公開で取得し、`f2b-api` の保護された `production` 環境の Secret `F2B_DEPLOY_CONFIG` に設定します。

収集側の通信は Cloudflare Access の Service Auth で保護し、収集元ごとに Service Token を使います。`workers.dev` とプレビュー URL は Wrangler 側で無効化します。

## CI と初回取り込みの注意

CI の `Terraform checks` は、認証情報を使わずに各 stack の `validate` や Terraform テストを実行します。ローカルでシェルと Workflow も確認したければ、次のようにします。

```sh
sudo pacman -S --needed shellcheck shfmt actionlint

shellcheck -x scripts/*.sh scripts/*.bash .github/scripts/*.sh
shfmt -d -i 2 -ci -sr scripts/*.sh scripts/*.bash .github/scripts/*.sh
actionlint -ignore 'unexpected key "queue" for "concurrency" section' \
  .github/workflows/*.yml
```

`concurrency.queue: max` は actionlint 1.7.12 で未認識なので、その警告だけ除外しています。

Provider のバージョンは各 stack の `.terraform.lock.hcl` で固定しています。更新時は Private 側の `deployment/config.json` と `trust/cloudflare.lock.hcl` も合わせる必要があります。Terraform CLI のバージョンも両リポジトリでそろえてください。

既存リソースの取り込みに使う `imports.tf` は、import と plan の確認が終わるまで削除しないでください。

また、R2 の Managed Domain、Lifecycle、CORS は、現在固定している Provider では import 非対応です。初回 plan で「作成」と表示されても、既存設定を更新する API 呼び出しになる場合があります。ここは特に注意して確認してください。

## 参考資料

- [Cloudflare Terraform の R2 backend](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Cloudflare WAF](https://developers.cloudflare.com/waf/)
- [Cloudflare Rate Limiting](https://developers.cloudflare.com/waf/rate-limiting-rules/)
- [Bot Fight Mode](https://developers.cloudflare.com/bots/get-started/bot-fight-mode/)
- [GitHub Actions の実行イベント](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
