resource "cloudflare_workers_script" "managed" {
  for_each = nonsensitive(toset(keys(var.workers)))

  account_id          = var.account_id
  script_name         = var.workers[each.key].name
  content_file        = abspath(var.workers[each.key].source_path)
  content_sha256      = filesha256(var.workers[each.key].source_path)
  main_module         = var.workers[each.key].main_module
  body_part           = var.workers[each.key].body_part
  files               = var.workers[each.key].files
  bindings            = var.workers[each.key].bindings
  keep_bindings       = var.workers[each.key].preserve_binding_types
  compatibility_date  = var.workers[each.key].compatibility_date
  compatibility_flags = var.workers[each.key].compatibility_flags
  usage_model         = var.workers[each.key].usage_model
  logpush             = var.workers[each.key].logpush
  observability       = var.workers[each.key].observability
  limits              = var.workers[each.key].limits
  placement           = var.workers[each.key].placement
  tail_consumers      = var.workers[each.key].tail_consumers

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_workers_cron_trigger" "managed" {
  for_each = nonsensitive(toset(keys(var.worker_crons)))

  account_id  = var.account_id
  script_name = cloudflare_workers_script.managed[var.worker_crons[each.key].worker_key].script_name
  schedules   = var.worker_crons[each.key].schedules
}

resource "cloudflare_workers_route" "managed" {
  for_each = nonsensitive(toset(keys(var.worker_routes)))

  zone_id = cloudflare_zone.managed[var.worker_routes[each.key].zone_key].id
  pattern = var.worker_routes[each.key].pattern
  script  = var.worker_routes[each.key].script
}

resource "cloudflare_workers_custom_domain" "managed" {
  for_each = nonsensitive(toset(keys(var.worker_domains)))

  account_id  = var.account_id
  hostname    = var.worker_domains[each.key].hostname
  service     = var.worker_domains[each.key].service
  environment = var.worker_domains[each.key].environment
  zone_id     = var.worker_domains[each.key].zone_id
}

resource "cloudflare_workers_script_subdomain" "managed" {
  for_each = nonsensitive(toset(keys(var.workers)))

  account_id       = var.account_id
  script_name      = cloudflare_workers_script.managed[each.key].script_name
  enabled          = var.workers[each.key].subdomain.enabled
  previews_enabled = var.workers[each.key].subdomain.previews_enabled
}
