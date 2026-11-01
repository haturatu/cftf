# Account Security モジュール

IP List と Turnstile は Zone ごとではなく、Cloudflare の Account に属するリソースです。

Zone の数だけ同じリストを作ろうとすると管理がややこしくなりますし、Free プランには件数の上限もあります。なので、この二つは `stacks/security-account` へまとめています。

`modules/account-security` はその共通定義です。state と backend はここでは管理せず、実際の操作は Private 側から行います。

## 管理するもの

| 入力 | 内容 |
| --- | --- |
| `account_id` | Cloudflare の Account ID |
| `ip_lists` | WAF から参照する IP Custom List |
| `turnstile_widgets` | ログインやフォームで使う Turnstile Widget |

Free プラン向けに、このモジュールでは次の件数を検証します。

| リソース | 上限 |
| --- | --- |
| IP Custom List | 1 Account に 1 リスト |
| IP List の項目 | 1 リスト最大 10,000 件 |
| Turnstile | 1 Account に最大 20 Widget |

この数値はプランや Cloudflare 側の仕様変更で変わる可能性があります。入力の型と検証内容は [variables.tf](variables.tf) を確認してください。

## IP List を作成する

IP List 自体は、IP アドレスの集合を定義する機能です。**リストを作るだけでは通信はブロックされません**。実際の制御は WAF の式とアクションで指定します。

```hcl
ip_lists = {
  allowed = {
    name        = "allowed_ips"
    description = "Trusted client networks"
    items = [
      { ip = "192.0.2.10", comment = "Documentation address" },
      { ip = "2001:db8::/32", comment = "Documentation network" }
    ]
  }
}
```

ここにある IP は説明用です。`name` は小文字英数字とアンダースコアの 1〜50 文字に制限しています。`items` は IPv4、IPv6、CIDR を指定できます。

WAF の式からは次のように参照します。

```text
ip.src in $allowed_ips
```

この式はリストに含まれる IP を判定するだけです。許可するか拒否するかは WAF ルール側の設定次第になります。

### 既存リストを import する場合

既存のリストがあるなら、`import_id` にそのリスト ID を指定します。

```hcl
ip_lists = {
  allowed = {
    import_id = "REPLACE_WITH_EXISTING_LIST_ID"
    name      = "allowed_ips"
    # items は省略
  }
}
```

実際の ID は非公開の tfvars に置いてください。

ここで少し危険なのが `items` の挙動です。

| 指定方法 | どうなるか |
| --- | --- |
| `items` を書かない | 既存の項目をそのまま保持 |
| `items = []` | **既存の項目をすべて削除** |
| `items = [...]` | 指定した内容でリストを管理 |

既存リストをとりあえず Terraform に取り込むだけなら、`items` は省略しておくのが安全です。

現在固定している Provider では、`items` を指定するとリスト全体の更新になるため、意図せず空にしてしまうと WAF の許可・拒否判定にも影響します。apply 前に plan を確認してください。

## Turnstile

Turnstile は、ログインやフォームの送信時に Bot かどうかを判定するための仕組みです。

Bot Fight Mode と違って、フォームなど必要な場所にだけ組み込めるのが利点です。ただし、Widget を作っただけでは何も保護されません。アプリケーション側でトークンを受け取り、Cloudflare の Siteverify API で検証する処理が必要です。

設定例は次のとおりです。

```hcl
turnstile_widgets = {
  login = {
    name    = "Login form"
    domains = ["example.invalid"]
    mode    = "managed"
  }
}
```

`example.invalid` は説明用のドメインです。

| 項目 | 値 |
| --- | --- |
| `mode` | `managed`、`non-interactive`、`invisible` |
| `domains` | 配置先のホスト名。空配列は不可 |
| `clearance_level` | `no_clearance`、`jschallenge`、`managed`、`interactive` |
| `region` | 省略すると `world` |
| `import_id` | 既存 Widget を取り込む場合の sitekey |

Enterprise 専用の `bot_fight_mode`、`ephemeral_id`、`offlabel` は、この Free 向けモジュールの入力には含めていません。

なお、sitekey はブラウザーへ公開する値ですが、**secret は別物**です。Terraform の state に含まれるため、state や plan の出力を公開しないでください。

## 既存 Account に適用するには

運用手順は Zone と大きく変わりません。

1. Private 側で Account 用の state キーを確認する。
2. [設定例](../../examples/security-account.tfvars.json.example)を参考に、非公開の R2 Config リビジョンへ値を登録する。
3. 既存の IP List や Turnstile がある場合は `import_id` を指定する。IP List の項目を触らないなら `items` は書かない。
4. `scripts/tf.sh security-account plan` で差分を確認する。
5. 意図しない作成・更新・削除がなければ、承認した環境で apply する。

R2 と Private リポジトリの関係は [トップレベル README](../../README.md#plan-と-apply) にまとめています。

## テスト

```sh
terraform -chdir=modules/account-security init -backend=false -input=false
terraform -chdir=modules/account-security test
```

これは入力の validation や Terraform 定義を検査するためのものです。実際の API 権限や Turnstile の動作、すでにある Cloudflare リソースとの一致は検証しません。

- [入力例](../../examples/security-account.tfvars.json.example)
- [import の定義](../../stacks/security-account/imports.tf)
- [Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/)
