<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Cloudflare の Terraform 管理](#cloudflare-%E3%81%AE-terraform-%E7%AE%A1%E7%90%86)
  - [構成](#%E6%A7%8B%E6%88%90)
  - [PR のラベルから apply する流れ](#pr-%E3%81%AE%E3%83%A9%E3%83%99%E3%83%AB%E3%81%8B%E3%82%89-apply-%E3%81%99%E3%82%8B%E6%B5%81%E3%82%8C)
  - [R2 の設定リビジョン](#r2-%E3%81%AE%E8%A8%AD%E5%AE%9A%E3%83%AA%E3%83%93%E3%82%B8%E3%83%A7%E3%83%B3)
  - [手動で plan する](#%E6%89%8B%E5%8B%95%E3%81%A7-plan-%E3%81%99%E3%82%8B)
  - [検証と初回取り込み](#%E6%A4%9C%E8%A8%BC%E3%81%A8%E5%88%9D%E5%9B%9E%E5%8F%96%E3%82%8A%E8%BE%BC%E3%81%BF)
  - [Bootstrap と復旧](#bootstrap-%E3%81%A8%E5%BE%A9%E6%97%A7)
  - [参考資料](#%E5%8F%82%E8%80%83%E8%B3%87%E6%96%99)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Cloudflare の Terraform 管理

Terraform のコードは Git、設定値と Worker ソースは非公開 R2、state は別の専用 R2 バケットで管理します。ドメイン名、Zone ID、バケット名、認証情報は公開コードに含めません。

## 構成

```text
cftf/
├── .github/workflows/         # 非機密の検証、ラベル承認、マージと実行要求
├── stacks/
│   ├── zone/                 # 全 Zone が共有する root
│   ├── r2/
│   └── workers/
├── modules/zone/             # 既存リソースアドレスを維持する共通定義
├── bootstrap/backend/        # State・Config バケットの初期構築と復旧専用
├── scripts/tf.sh             # 共通の手動実行窓口
├── examples/
└── .private/                 # Git 管理外の一時データと診断ログ
```

Zone の違いは非公開の入力値と state キーだけです。`zone-001` などの匿名ターゲットを、Private 側の許可リストで管理します。Zone の追加時に Terraform ファイルを複製する必要はありません。

`stacks/zone` は `module.zone` のリソースアドレスを維持します。各ターゲットの `TF_DATA_DIR` と既存の state キーを分け、同じ root を使っても state が混ざらない構成です。`init -reconfigure` は選択した backend を初期化する処理であり、state の移行は行いません。

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
r2.tfvars.json
workers.tfvars.json
workers/...
manifest.json
```

`backend.hcl` は共通のバケット名、エンドポイント、S3 互換設定を持ち、state キーを含みません。実行側の許可リストがターゲットごとの既存キーを指定します。Config と State のバケットは別にします。

JSON 形式の tfvars は Terraform 標準の入力形式です。Zone 設定の動的な値は `value_json`、ルール配列は `rules_json` として保持します。Worker のソースパスはダウンロード先の絶対パスに置き換えます。

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
```

`apply` を指定すると、同じ処理で plan を作成・検査してから、その保存済み plan を適用します。任意の Terraform オプションや未知のターゲットは受け付けません。

```sh
./scripts/tf.sh zone-001 apply
```

通常出力は固定の状態のみです。詳細ログ、設定の一時ファイル、保存した plan は `.private/runtime/` に置きます。アクセス権はディレクトリ `700`、ファイル `600` とし、公開しないでください。CI はローカル端末の `.private/` を参照しません。

## 検証と初回取り込み

GitHub API はモックし、ネットワーク接続なしで承認、マージ、実行要求を検証します。

依存関係としてシェルの静的解析には `shellcheck`、Workflow の検証には `actionlint` を使います。

### インストール
```sh
sudo pacman -S --needed shellcheck shfmt actionlint
```

### テスト
```sh
terraform fmt -check -recursive
.github/scripts/control.test.sh
./scripts/tf.test.sh
shellcheck -x scripts/*.sh scripts/*.bash .github/scripts/*.sh
shfmt -d -i 2 -ci -sr scripts/*.sh scripts/*.bash .github/scripts/*.sh
terraform -chdir=modules/zone init -backend=false -input=false
terraform -chdir=modules/zone test
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
