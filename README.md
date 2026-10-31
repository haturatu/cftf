# Cloudflare の Terraform 管理

Cloudflare のリソースを、匿名の Zone 単位とアカウントの用途単位で管理します。実際のドメイン、リソース名、識別子、設定値、Worker ソースは `.private/` に、認証情報は `.env` に置きます。これらは Git 管理から除外します。

## 構成

```text
cftf/
├── .env.example
├── .private/                     # Git 管理外
│   ├── zone-001.tfvars
│   ├── zone-001.backend.hcl
│   ├── personal-r2.tfvars
│   ├── personal-r2.backend.hcl
│   └── ...
├── accounts/personal/
│   ├── backend/                  # 専用 state バケットの管理
│   ├── r2/                       # アプリ用バケットの管理
│   ├── workers/
│   └── zones/
│       ├── zone-001/
│       ├── zone-002/
│       └── zone-003/
├── examples/
└── modules/zone/
    ├── main.tf
    ├── variables.tf
    ├── dns.tf
    ├── settings.tf
    └── rulesets.tf
```

`zone-001` などの名前はローカルの管理用識別子です。Cloudflare の Zone ID やドメイン名とは関係ありません。各ディレクトリが独立したルートモジュールであり、独立した state を持ちます。

Zone の共通定義は `modules/zone` にまとめています。Zone の root にある `imports.tf` が、その Zone に属する既存リソースを子モジュールへ取り込みます。

## 前提条件

- Terraform 1.10 以上、2.0 未満
- Cloudflare API トークン
- 専用 R2 バケットと、そのバケットへアクセスできる S3 互換の認証情報
- 非公開の変数ファイル、backend 設定、Worker ソースのバックアップ

Provider は各 root の `versions.tf` と `.terraform.lock.hcl` で固定しています。R2 backend に使用するバケットは専用とし、アプリ用バケットと共有しません。

## 認証情報と非公開設定

既存の `.env` と `.private/` は上書きせずに使用してください。新しい環境では `.env.example` と `examples/` の設定例をコピーし、非公開の値を入力します。認証情報を入力したファイルのアクセス権は `600`、`.private/` は `700` にします。

Terraform は `.env` を自動で読み込みません。リポジトリルートで、内容を確認した自分の `.env` を読み込みます。

```sh
umask 077
set -a
. ./.env
set +a
```

各 root には、対応する `.tfvars` と `.backend.hcl` を指定します。

| Root | 変数ファイル | Backend 設定 |
| --- | --- | --- |
| `accounts/personal/zones/zone-001` | `.private/zone-001.tfvars` | `.private/zone-001.backend.hcl` |
| `accounts/personal/zones/zone-002` | `.private/zone-002.tfvars` | `.private/zone-002.backend.hcl` |
| `accounts/personal/zones/zone-003` | `.private/zone-003.tfvars` | `.private/zone-003.backend.hcl` |
| `accounts/personal/r2` | `.private/personal-r2.tfvars` | `.private/personal-r2.backend.hcl` |
| `accounts/personal/workers` | `.private/personal-workers.tfvars` | `.private/personal-workers.backend.hcl` |
| `accounts/personal/backend` | `.private/personal-backend.tfvars` | `.private/personal-backend.backend.hcl` |

`.backend.hcl` にはバケット名、保存キー、エンドポイント、R2 互換設定を置きます。認証キーは環境変数で渡します。各 root の保存キーを重複させないでください。`use_lockfile = true` により、同じ state に対する同時操作を防ぎます。

## 検証と取り込み

Zone の操作例です。リポジトリルートから実行します。

```sh
terraform -chdir=accounts/personal/zones/zone-001 init -input=false \
  -backend-config=../../../../.private/zone-001.backend.hcl
terraform -chdir=accounts/personal/zones/zone-001 validate
terraform -chdir=accounts/personal/zones/zone-001 plan -input=false \
  -var-file=../../../../.private/zone-001.tfvars \
  -out=../../../../.private/zone-001.tfplan
```

R2、Workers、backend のディレクトリから `.private/` への相対パスは `../../../.private/` です。R2 の操作例は次のとおりです。

```sh
terraform -chdir=accounts/personal/r2 init -input=false \
  -backend-config=../../../.private/personal-r2.backend.hcl
terraform -chdir=accounts/personal/r2 plan -input=false \
  -var-file=../../../.private/personal-r2.tfvars \
  -out=../../../.private/personal-r2.tfplan
```

`plan` は取り込みや設定変更を適用しません。既存設定との一致、Secret の保持、削除や置き換えがないことを確認してから、対象 root で保存した plan を適用します。

```sh
terraform -chdir=accounts/personal/zones/zone-001 apply \
  ../../../../.private/zone-001.tfplan
```

Provider の制約により、R2 の公開設定、ライフサイクル、CORS は import できません。既存設定を再現していても、初回 plan では追加として表示されます。Worker も、ソースのパスやハッシュ、Cron の取り込み状態により、初回に更新が表示される場合があります。

## 型と入力検証

R2 と Worker の設定は `map(object(...))` で定義しています。ID の形式、R2 のリージョンと管轄、ローカル Worker キーの参照先などを `validation` で検証します。

R2 の公開は、同じバケットに `public_access_enabled = true` と `allow_public_access = true` の両方を指定した場合だけ許可します。state 専用バケットの公開は許可しません。

Zone 設定の値は `value_json`、ルールセットの可変のルール配列は `rules_json` に JSON 文字列として渡します。メタデータは明示した型で検証し、JSON は構文を検証してから Provider に渡します。DNS の `data.flags` だけは、Provider が動的型を要求するため `any` を使用します。

Worker の `source_path` には非公開ソースの絶対パスを指定します。Secret の値は Terraform 入力に含めず、`preserve_binding_types` で既存の Secret を保持します。`secret_names` は値を含まない確認用の一覧です。Cron、ルート、カスタムドメインは `worker_key` で同じ root の Worker を参照します。

Zone 内の DNS、設定、ルールセットはモジュール内部でその Zone を参照するため、別の Zone のキーを入力する必要はありません。Cloudflare の managed ruleset 本体は管理しません。

## テスト

全体のフォーマットと、認証情報を使用しない Zone モジュールの入力検証テストを実行できます。

```sh
terraform fmt -check -recursive
terraform -chdir=modules/zone init -backend=false -input=false
terraform -chdir=modules/zone test
terraform -chdir=accounts/personal/backend test
```

各 root の `validate` と非公開設定を使った `plan` も、変更した単位で実行してください。

## State と復旧

state は専用の非公開 R2 バケットに保管します。backend を管理する root 自身の state も、バケット作成後に同じ専用バケットへ移します。専用バケットには `prevent_destroy` を設定しています。

専用バケットがまだ存在しない初回だけは、backend root を一時的に local backend で実行し、バケット作成後に S3 backend へ戻して `terraform init -migrate-state` で移行します。既存 backend の再初期化や復旧時に、バケットを重複作成しないでください。

R2 は S3 のバージョニング API に対応していません。`.env`、`.tfvars`、`.backend.hcl`、Worker ソース、state のスナップショットは、暗号化とアクセス制御のある別の非公開ストレージへバックアップしてください。ロックファイルを保管期限付きの bucket lock で固定すると Terraform のロック解除を妨げるため、設定しないでください。

Terraform の出力、state、保存した plan、`terraform show -json` の結果、デバッグログには本番の情報が含まれます。公開せずに扱ってください。リポジトリを clone しただけでは、本番の値を復元できません。

## 参考資料

- [Terraform 設計ガイドライン](https://future-architect.github.io/arch-guidelines/documents/forTerraform/terraform_guidelines.html)
- [Cloudflare の R2 backend](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Terraform の機密情報の管理](https://developer.hashicorp.com/terraform/language/manage-sensitive-data)
- [R2 の S3 互換 API](https://developers.cloudflare.com/r2/api/s3/api/)
