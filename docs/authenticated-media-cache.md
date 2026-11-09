# 認証付きメディアキャッシュの管理

このWorkerは、画像と動画を認証後にキャッシュします。Workerソースと実環境設定は、Hatena Workerと同じく非公開R2 Config revisionで管理します。公開リポジトリには挙動の説明と、環境値を含まないTerraform設定例だけを置きます。

## Workerの動作

- メディア要求ごとに認証用ルートへ`HEAD`を送り、認証成功後にキャッシュを参照します。
- 画像と動画だけをWorker Cache APIに保存します。キャッシュキーには認証CookieのSHA-256値を含め、Cookie値そのものはキーに保存しません。
- Worker Cache APIと認証済みブラウザー応答のTTLは1年です。ブラウザー応答は`private`とし、`Vary: Cookie`でCookieごとに分けます。
- 未認証応答と認証に失敗した応答は`private, no-store`です。

同じCookie値のままサーバー側でセッションだけを失効させた場合、ブラウザーは保存済みのメディアを期限まで表示する可能性があります。Cookieが変わると別のブラウザーキャッシュとして扱われます。

## 公開資産のCache Response Rule

[zoneの例](../examples/zone.tfvars.json.example)には、`http_response_cache_settings` phaseで公開資産のTTLを設定する例があります。

- ブラウザー: 5分
- Cloudflareエッジ: 1日
- `immutable`付きの資産: 例のルールから除外し、オリジンの長期TTLを維持

Cache Response RuleはTerraformの`cloudflare_ruleset`として管理できます。既存ルールを取り込む場合は、実際のRuleset IDを非公開Configに設定してからplanを確認します。

## 非公開Config revision

Workerソースと環境設定はPrivate側で編集し、R2 Configの新しいrevisionに保存します。

- Workerソースは`workers/authenticated_media_cache/worker.js`に置きます。
- `workers.tfvars.json`の`source_path`はそのファイルを指し、revision内では`__CFTF_PRIVATE_DIR__`から始まるパスに変換されます。
- Zone名、Zone ID、Ruleset ID、Worker名、Route ID、Routeパターン、state keyも非公開Configに置きます。

revisionは上書きしません。変更ごとにmanifestとSHA-256を作り、新しいrevisionとして固定します。アカウント単位のWorkerはHatena Workerと同じ既存の`workers` targetとstateに追加します。Worker用の別targetやstateは作りません。

## Workers stateへの登録

1. Private側の手順で現在の承認済みConfig revisionを安全な編集ディレクトリへ取得します。
2. Workerソースをそのディレクトリ内の`workers/authenticated_media_cache/worker.js`に置き、`workers.tfvars.json`の`workers`へ定義を追加します。`source_path`には編集ディレクトリ内のファイルパスを指定します。
3. `worker_routes`にサムネイル、コンテンツ、ダウンロードの3パターンを登録します。それぞれ既存RouteのID、Zone ID、パターン、Worker aliasを設定します。[Workers設定例](../examples/workers.tfvars.json.example)を参照してください。
4. Cloudflare上に既にあるWorker script、script subdomain、Routeは、実IDを使ってTerraformのimport blockへ取り込みます。
5. Private側の手順で編集済みConfigを新しいR2 revisionとして発行します。内容を確認して`CONFIG_REVISION`と`CONFIG_MANIFEST_SHA256`を更新し、Privateのplanで差分を確認してから承認済みapplyを実行します。

Workerソースの変更履歴もR2の不変revisionで管理します。公開GitにはWorker本体や実環境値を含めません。

## Importと反映

Cloudflare上にあるWorker、Route、Cache Response RuleをTerraform管理へ移すときは、実リソースIDを使ったimport設定を追加します。planで既存設定に意図しない変更がないことを確認してから、Private側のデプロイ手順でapplyします。

例のホスト名とIDは説明用です。実際の値は非公開Configだけに置きます。
