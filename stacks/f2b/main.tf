resource "cloudflare_zero_trust_organization" "managed" {
  count                   = var.access_organization == null ? 0 : 1
  account_id              = var.account_id
  name                    = var.access_organization.name
  auth_domain             = var.access_organization.auth_domain
  deny_unmatched_requests = false
  lifecycle { prevent_destroy = true }
}
resource "cloudflare_d1_database" "managed" {
  account_id = var.account_id
  name       = var.database_name
  lifecycle { prevent_destroy = true }
}
resource "cloudflare_zero_trust_access_service_token" "source" {
  for_each   = var.sources
  account_id = var.account_id
  name       = "f2b-${each.key}"
  duration   = "8760h"
  depends_on = [cloudflare_zero_trust_organization.managed]
  lifecycle { prevent_destroy = true }
}
resource "cloudflare_workers_script" "managed" {
  for_each           = var.workers
  account_id         = var.account_id
  script_name        = each.value.name
  content_file       = each.value.source_path
  content_sha256     = filesha256(each.value.source_path)
  main_module        = basename(each.value.source_path)
  compatibility_date = "2026-10-31"
  usage_model        = "standard"
  bindings = concat([
    { name = "DB", type = "d1", id = cloudflare_d1_database.managed.id },
    { name = "STALE_SECONDS", type = "plain_text", text = "172800" }
    ], each.key == "ingest" ? [{
      name = "SOURCE_TOKENS", type = "json", json = jsonencode({
        for name, source in var.sources : cloudflare_zero_trust_access_service_token.source[name].client_id => { source = name, jails = sort(tolist(source.jails)) }
      })
  }] : [])
  lifecycle { prevent_destroy = true }
}
resource "cloudflare_workers_script_subdomain" "disabled" {
  for_each         = var.workers
  account_id       = var.account_id
  script_name      = cloudflare_workers_script.managed[each.key].script_name
  enabled          = false
  previews_enabled = false
}
resource "cloudflare_zero_trust_access_application" "ingest" {
  account_id                = var.account_id
  name                      = "Fail2ban ingestion"
  domain                    = var.workers["ingest"].hostname
  type                      = "self_hosted"
  app_launcher_visible      = false
  session_duration          = "24h"
  service_auth_401_redirect = false
  policies = [{
    name    = "Collection service tokens", decision = "non_identity", precedence = 1,
    include = [for token in cloudflare_zero_trust_access_service_token.source : { service_token = { token_id = token.id } }]
  }]
  lifecycle { prevent_destroy = true }
}
resource "cloudflare_workers_custom_domain" "managed" {
  for_each   = var.workers
  account_id = var.account_id
  zone_id    = var.zone_id
  hostname   = each.value.hostname
  service    = cloudflare_workers_script.managed[each.key].script_name
  depends_on = [cloudflare_zero_trust_access_application.ingest, cloudflare_workers_script_subdomain.disabled]
  lifecycle { prevent_destroy = true }
}
output "database_id" {
  value     = cloudflare_d1_database.managed.id
  sensitive = true
}
output "collector_credentials" {
  sensitive = true
  value = { for name, token in cloudflare_zero_trust_access_service_token.source : name => {
    source   = name, client_id = token.client_id, client_secret = token.client_secret,
    endpoint = "https://${var.workers["ingest"].hostname}/v1/ingest/snapshot"
  } }
}
