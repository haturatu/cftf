# Cloudflare の Terraform 管理

Cloudflare の既存リソースを Terraform で管理するための構成です。ドメイン、リソース名、識別子、設定値、Worker のコードはローカルの `.private/` に置きます。認証情報は `.env` に置きます。

Git には Terraform 定義、変数の型、Provider の lock ファイル、値を含まない設定例と実行手順を保存します。公開リポジトリへ変更しても、これらのファイルに本番の値が含まれない構成です。

## 前提条件

- Terraform 1.10 以上、2.0 未満
- 対象リソースの読み取り権限を持つ Cloudflare API トークン。変更の適用時には書き込み権限も必要です。
- 非公開の変数ファイルと Worker ソースのバックアップ

Provider のバージョンは `versions.tf` と `.terraform.lock.hcl` で固定しています。

## ローカル設定

新しい環境では、設定例をコピーして値を入力します。既存の `.env` や `.private/` がある場合は、上書きせずに使用します。

```sh
umask 077
mkdir -p .private
chmod 700 .private
cp .env.example .env
cp examples/config.tfvars.json.example .private/config.tfvars.json
chmod 600 .env .private/config.tfvars.json
```

`.env` の `CF_API_TOKEN` に認証トークンを設定します。Terraform は `.env` を自動で読み込みません。内容を確認した自分の `.env` を、次のように読み込みます。

```sh
set -a
. ./.env
set +a
export CLOUDFLARE_API_TOKEN="$CF_API_TOKEN"
```

Account ID などの本番の値は `.private/config.tfvars.json` に入力します。`.env` の Account ID と一致させてください。変数の構造は `variables.tf` を参照してください。

| 変数 | 内容 |
| --- | --- |
| `account_id` | 対象の Account ID |
| `zones` | ゾーンの ID、名前、種類、停止状態 |
| `zone_settings` | ゾーンを参照するキー、設定 ID、設定値 |
| `dns_records` | レコードの ID、ゾーンを参照するキー、DNS の実値 |
| `buckets` | 名前、リージョン、管轄、公開状態、ライフサイクル、CORS |
| `workers` | 名前、非公開ソースのパス、binding、実行設定、公開状態 |
| `worker_crons` | Worker を参照するキーと Cron 設定 |
| `worker_routes` | ゾーンを参照するキー、ルート ID、パターン、スクリプト |
| `worker_domains` | カスタムドメインの ID、ホスト名、サービス、ゾーン ID |
| `rulesets` | 利用者が管理するゾーンのルールセット |

各マップのキーには、実名を含まない任意の管理用エイリアスを使います。Terraform のリソースアドレスに使うため、取り込み後はキーを安易に変更しないでください。

Worker の `source_path` はリポジトリルートからの相対パスです。`.private/` 内のファイルを指定します。OAuth トークンなどの Secret の値は変数ファイルへコピーせず、Cloudflare 側で保持します。`preserve_binding_types` で既存の Secret binding の種類を保持し、`secret_names` には確認用の名前だけを保存します。

## 検証と取り込み

```sh
terraform init -input=false
terraform fmt -check
terraform validate
terraform plan -input=false \
  -var-file=.private/config.tfvars.json \
  -out=.private/migration.tfplan
```

`imports.tf` は変数に指定した既存リソースを取り込み対象にします。`plan` は構成を照合するだけで、取り込みや設定変更の適用は行いません。

Provider の制約により、R2 の公開設定、ライフサイクル、CORS は import できません。既存設定をコード化しても、初回の plan では追加として表示されます。初回の apply は、バケットの新規作成ではなく、これらの設定 API への書き込みを含みます。Worker も、取得したソースのファイルパスやハッシュを管理し始めるため、初回に更新が表示される場合があります。

既存設定との一致、Secret の保持、削除や置き換えがないことを確認してから、保存した plan を適用します。

```sh
terraform apply .private/migration.tfplan
```

ゾーン、DNS レコード、R2 バケット、Worker には `prevent_destroy` を設定しています。Cloudflare が提供する managed ruleset 本体は管理対象に含めません。

## 非公開ファイルの保管

state は `.private/terraform.tfstate` に保存します。`.private/` と `.env` は Git で除外しています。GitHub のプライベート設定だけに依存せず、認証情報と本番の設定値をリポジトリから分離します。

Terraform の通常出力にもリソース名や識別子が含まれます。特に state、保存した plan、`terraform show -json` の出力、Provider のデバッグログを公開しないでください。`sensitive` は表示の抑制機能であり、state の暗号化や Git からの除外を行うものではありません。

`.env`、変数ファイル、Worker ソース、state を、アクセス制御と暗号化のある非公開ストレージへバックアップしてください。リポジトリだけを clone しても、本番の値は復元できません。

複数の環境から同時に操作する場合は、アクセス制御、暗号化、ロックに対応した非公開のリモート backend へ移行してください。この構成は専用バケットや認証情報を自動作成しません。

## 参考資料

- [Cloudflare リソースの取り込み](https://developers.cloudflare.com/terraform/advanced-topics/import-cloudflare-resources/)
- [Terraform の機密情報の管理](https://developer.hashicorp.com/terraform/language/manage-sensitive-data)
- [R2 の公開設定](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.1/docs/resources/r2_managed_domain)
- [R2 のライフサイクル設定](https://registry.terraform.io/providers/cloudflare/cloudflare/5.28.1/docs/resources/r2_bucket_lifecycle)
