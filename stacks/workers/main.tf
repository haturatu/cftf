resource "cloudflare_workers_script" "managed" {
  for_each = var.workers

  account_id          = var.account_id
  script_name         = each.value.name
  content_file        = each.value.source_path
  content_sha256      = filesha256(each.value.source_path)
  main_module         = each.value.main_module
  body_part           = each.value.body_part
  bindings            = each.value.bindings
  keep_bindings       = each.value.preserve_binding_types
  compatibility_date  = each.value.compatibility_date
  compatibility_flags = each.value.compatibility_flags
  usage_model         = each.value.usage_model
  logpush             = each.value.logpush
  observability       = each.value.observability

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_workers_cron_trigger" "managed" {
  for_each = var.worker_crons

  account_id  = var.account_id
  script_name = cloudflare_workers_script.managed[each.value.worker_key].script_name
  schedules   = each.value.schedules
}

resource "cloudflare_workers_route" "managed" {
  for_each = var.worker_routes

  zone_id = each.value.zone_id
  pattern = each.value.pattern
  script  = each.value.worker_key == null ? null : cloudflare_workers_script.managed[each.value.worker_key].script_name
}

resource "cloudflare_workers_custom_domain" "managed" {
  for_each = var.worker_domains

  account_id  = var.account_id
  hostname    = each.value.hostname
  service     = cloudflare_workers_script.managed[each.value.worker_key].script_name
  environment = each.value.environment
  zone_id     = each.value.zone_id
}

resource "cloudflare_workers_script_subdomain" "managed" {
  for_each = var.workers

  account_id       = var.account_id
  script_name      = cloudflare_workers_script.managed[each.key].script_name
  enabled          = each.value.subdomain.enabled
  previews_enabled = each.value.subdomain.previews_enabled
}
