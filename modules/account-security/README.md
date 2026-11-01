# Account Security モジュール

`modules/account-security` は、複数の Cloudflare Zone から共通で使用する **Account 単位の IP Custom List と Turnstile Widget** を Terraform で管理します。Zone ごとの state とは分離し、`stacks/security-account` の root から使用します。

**重要:** このモジュールは state / backend を所有しません。実際の Account ID、既存リスト ID、Turnstile の sitekey は非公開の tfvars で渡してください。Turnstile の secret は Terraform state に格納されます。

## 入力

| 入力 | 型 | 内容 |
| --- | --- | --- |
| `account_id` | `string` | Cloudflare Account の 32 桁 ID |
| `ip_lists` | `map(object)` | WAF から参照する IP Custom List |
| `turnstile_widgets` | `map(object)` | フォームやログインに使う Turnstile Widget |

Free プランでの、このモジュールの検証上限は次のとおりです。

| リソース | 上限 |
| --- | --- |
| IP Custom List | 1 Account あたり 1 リスト |
| リスト内の IP | 1 リストあたり最大 10,000 項目 |
| Turnstile | 1 Account あたり最大 20 Widget |

この上限はプランや Cloudflare の仕様変更によって変わる可能性があります。型と検証条件は [variables.tf](variables.tf) に定義されています。

## IP Custom List

### 新しいリストを定義する

`ip_lists` ではマップキーを識別子として使い、各リストに `name`、必要に応じて `description` と `items` を指定します。

```hcl
ip_lists = {
  allowed = {
    name        = "allowed_ips"
    description = "Trusted client networks"
    items = [
      { ip = "192.0.2.10", comment = "Documentation address" },
      { ip = "2001:db8::/32", comment = "Documentation network" },
    ]
  }
}
```

上記の IP は説明用のアドレスです。リストの `name` には小文字の英数字とアンダースコアを使用し、1～50 文字で指定してください。`items` は IPv4、IPv6、CIDR を受け付けます。

WAF からは、作成したリスト名を式で参照できます。

```text
ip.src in $allowed_ips
```

この式は IP リストを参照する条件の例です。**許可・拒否の動作は WAF ルールのアクションで決まります**。IP リストを作成するだけでは、対象 IP を許可したりブロックしたりしません。

### 既存リストを import する

既存の IP Custom List を管理する場合は `import_id` にリスト ID を設定します。`stacks/security-account/imports.tf` が取り込み用 ID を組み立てます。

```hcl
ip_lists = {
  allowed = {
    import_id = "REPLACE_WITH_EXISTING_LIST_ID"
    name      = "allowed_ips"
    # items は指定しない
  }
}
```

**注意:** このコードは指定方法の説明用です。`import_id` は実際の 32 桁の ID に置き換え、公開コードに記録しないでください。

**`items` の省略と空配列は異なります。**

| 指定 | 挙動 |
| --- | --- |
| `items` を省略 | 既存のリスト項目を保持 |
| `items = []` | 既存の全項目を削除 |
| `items = [...]` | 指定した項目でリスト内容を管理 |

固定した Provider では、`items` を指定するとリスト全体の更新につながります。取り込みだけを行う場合は `items` を省略し、plan で予期しない項目変更がないことを確認してください。

## Turnstile Widget

Turnstile は、フォーム送信やログインの際に Bot を判定するために使用します。Cloudflare の DNS や WAF と同一の Zone である必要はありません。

`turnstile_widgets` の各要素に、`name`、`domains`、`mode`、必要に応じて `clearance_level` と `region` を指定します。

```hcl
turnstile_widgets = {
  login = {
    name    = "Login form"
    domains = ["example.invalid"]
    mode    = "managed"
  }
}
```

`example.invalid` は説明用のドメインです。実際の適用先は非公開の設定で指定してください。

| 項目 | 対応する値・条件 |
| --- | --- |
| `mode` | `managed`、`non-interactive`、`invisible` |
| `domains` | ホスト名の配列（空は不可） |
| `clearance_level` | `no_clearance`、`jschallenge`、`managed`、`interactive`（省略可） |
| `region` | 省略時は `world` |
| `import_id` | 既存 Widget を import する場合の sitekey |

Cloudflare Enterprise 専用の `bot_fight_mode`、`ephemeral_id`、`offlabel` はこのモジュールの入力として公開していません。

**重要:** Widget を作成するだけではサイトのフォームが保護されるわけではありません。アプリケーション側でトークンを受け取り、Cloudflare の Siteverify API で検証する処理が必要です。また、公開してよい sitekey と、公開してはいけない secret を混同しないでください。

## 既存 Account の管理手順

1. 対象 Account に対する **専用の state キー**が、Private 側で登録されていることを確認します。
2. [入力ファイルの例](../../examples/security-account.tfvars.json.example)を参考に、非公開 R2 の Config リビジョンへ設定を保存します。
3. 既存 IP List / Turnstile を管理する場合は、`import_id` を指定します。IP List の既存項目を変えない場合は `items` を省略します。
4. `scripts/tf.sh security-account plan` で Private 側の plan を確認し、意図しない作成・変更・削除がないことを確かめます。
5. 承認・バックアップ・復旧の条件が揃った場合に限り apply します。

実行の仕組みと state の扱いは [トップレベル README](../../README.md#設定を-plan--apply-する) を参照してください。

## テスト

認証情報なしで入力検証を実行する場合は、リポジトリのルートで次のコマンドを使います。

```sh
terraform -chdir=modules/account-security init -backend=false -input=false
terraform -chdir=modules/account-security test
```

テストは Terraform モジュールの入力と定義を確認するためのものです。実際の API 権限、既存リソースの状態、Turnstile の Siteverify 動作を検証するものではありません。

## 参考資料

- [Account Security の非公開入力例](../../examples/security-account.tfvars.json.example)
- [既存資源の import 定義](../../stacks/security-account/imports.tf)
- [Cloudflare Turnstile の Free プラン](https://developers.cloudflare.com/turnstile/plans/)
- [Cloudflare WAF の Custom Lists](https://developers.cloudflare.com/waf/)
