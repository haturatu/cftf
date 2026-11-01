resource "cloudflare_zero_trust_organization" "managed" {
  count                   = var.access_organization == null ? 0 : 1
  account_id              = var.account_id
  name                    = var.access_organization.name
  auth_domain             = var.access_organization.auth_domain
  deny_unmatched_requests = false
  lifecycle { prevent_destroy = true }
}
resource "cloudflare_d1_database" "managed" {
  account_id       = var.account_id
  name             = var.database_name
  read_replication = { mode = "disabled" }
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
# The application Workers are deployed by haturatu/f2b-api with Wrangler.
# Forget the existing scripts without deleting them so Terraform stops
# managing their source, bindings, and versions.
removed {
  from = cloudflare_workers_script.managed
  lifecycle { destroy = false }
}
removed {
  from = cloudflare_workers_script_subdomain.disabled
  lifecycle { destroy = false }
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
  service    = each.value.name
  depends_on = [cloudflare_zero_trust_access_application.ingest]
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
    endpoint = "https://${var.workers["ingest"].hostname}/v1/ingest/snapshot/${name}"
  } }
}

resource "cloudflare_ruleset" "api_browser_checks" {
  zone_id     = var.zone_id
  name        = "API clients"
  description = "Allow non-browser REST clients on the two API hosts without bypassing Access."
  kind        = "zone"
  phase       = "http_request_firewall_custom"
  rules = [{
    action            = "skip"
    action_parameters = { products = ["bic"] }
    expression        = format("http.host in {%s}", join(" ", [for worker in values(var.workers) : jsonencode(worker.hostname)]))
    description       = "REST clients do not require browser integrity checks"
    enabled           = true
    logging           = { enabled = true }
  }]
  lifecycle { prevent_destroy = true }
}

resource "cloudflare_zero_trust_access_application" "source" {
  for_each                  = var.sources
  account_id                = var.account_id
  name                      = "Fail2ban ${each.key} ingestion"
  domain                    = "${var.workers["ingest"].hostname}/v1/ingest/snapshot/${each.key}"
  type                      = "self_hosted"
  app_launcher_visible      = false
  session_duration          = "24h"
  service_auth_401_redirect = false
  policies = [{
    name    = "Assigned collection service", decision = "non_identity", precedence = 1,
    include = [{ service_token = { token_id = cloudflare_zero_trust_access_service_token.source[each.key].id } }]
  }]
  lifecycle { prevent_destroy = true }
}

# Private inputs for the Wrangler deployment in haturatu/f2b-api.
# Export this value only into the protected GitHub environment.
output "deployment_config" {
  description = "D1, Worker names, Access audiences, and binding settings for the application deployment."
  sensitive   = true
  value = {
    account_id    = var.account_id
    database_name = var.database_name
    database_id   = cloudflare_d1_database.managed.id
    workers = {
      for key, worker in var.workers : key => {
        name     = worker.name
        hostname = worker.hostname
      }
    }
    source_scopes = {
      for name, application in cloudflare_zero_trust_access_application.source : application.aud => {
        source = name
        jails  = sort(tolist(var.sources[name].jails))
      }
    }
    stale_seconds = "172800"
    rate_limit = {
      namespace_id = "1001"
      limit        = 120
      period       = 60
    }
  }
}
