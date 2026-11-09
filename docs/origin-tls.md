# Cloudflare と Origin 間の TLS

この構成では、Cloudflare Origin CA 証明書を使って Cloudflare と Nginx の間を TLS で接続します。訪問者向けの証明書とは別に、Origin 上の Nginx に証明書と秘密鍵が必要です。

## 設定

`origin_cloud_regions` に Origin の IP、クラウド事業者、リージョンを設定します。Oracle Cloud の例は `vendor = "oci"`、`region = "ap-tokyo-1"` です。

`origin_ca_certificates` には Origin 上で生成した CSR と証明書のホスト名を渡します。秘密鍵は Terraform、Git、R2 の設定ファイルへ入れません。Terraform state には CSR と発行済み証明書が保存されます。

Zone の `settings` では `origin_max_http_version` を `2` にします。Nginx が TLS を受け付ける前に `ssl` を `strict` に変更すると、Cloudflare から Origin へ接続できなくなります。

## 適用順序

1. Origin 上で秘密鍵と CSR を生成します。秘密鍵は root のみ読み取れる場所へ保存します。
2. 非公開の Terraform 設定へ CSR、Origin IP、リージョンを追加し、Cloudflare Origin CA 証明書と Cloud Region Hint を適用します。`ssl` は現在の値のままにします。
3. `origin_ca_certificates` の機密出力から証明書を取得して Origin へ配置し、Nginx の TLS リスナーを有効にします。`nginx -t` と Origin への TLS 接続を確認します。
4. 最後に Cloudflare の `ssl` を `strict` にして適用します。

## 秘密鍵の生成例

次の例は P-256 の秘密鍵と CSR を作ります。`example.invalid` は対象の Origin ホスト名に置き換えます。

```sh
umask 077
openssl ecparam -name prime256v1 -genkey -noout -out origin.key
openssl req -new -key origin.key \
  -subj "/CN=example.invalid" \
  -addext "subjectAltName=DNS:example.invalid" \
  -out origin.csr
```

Cloudflare Origin CA はブラウザー向けの公開 CA 証明書ではありません。Origin への接続を Cloudflare 経由に限定し、Cloudflare 側を Full (strict) に設定して使用します。
