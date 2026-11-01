resource "cloudflare_url_normalization_settings" "managed" {
  count   = var.url_normalization == null ? 0 : 1
  zone_id = cloudflare_zone.managed.id
  scope   = var.url_normalization.scope
  type    = var.url_normalization.type
}

resource "cloudflare_zone_dnssec" "managed" {
  count   = var.dnssec == null ? 0 : 1
  zone_id = cloudflare_zone.managed.id
  status  = var.dnssec.status

  dnssec_use_nsec3    = try(var.dnssec.dnssec_use_nsec3, null)
  dnssec_multi_signer = try(var.dnssec.dnssec_multi_signer, null)
  dnssec_presigned    = try(var.dnssec.dnssec_presigned, null)
}

resource "cloudflare_leaked_credential_check" "managed" {
  count   = var.leaked_credential_check == null ? 0 : 1
  zone_id = cloudflare_zone.managed.id
  enabled = var.leaked_credential_check
}

resource "cloudflare_authenticated_origin_pulls_settings" "managed" {
  count   = var.authenticated_origin_pulls == null ? 0 : 1
  zone_id = cloudflare_zone.managed.id
  enabled = var.authenticated_origin_pulls
}
