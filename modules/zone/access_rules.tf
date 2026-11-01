resource "cloudflare_access_rule" "managed" {
  for_each = var.access_rules

  zone_id = cloudflare_zone.managed.id
  mode    = each.value.mode
  notes   = each.value.notes
  configuration = {
    target = each.value.target
    value  = each.value.value
  }
}

resource "cloudflare_user_agent_blocking_rule" "managed" {
  for_each = var.user_agent_blocking_rules

  zone_id     = cloudflare_zone.managed.id
  mode        = each.value.mode
  description = each.value.description
  paused      = each.value.paused
  configuration = {
    target = "ua"
    value  = each.value.value
  }
}
