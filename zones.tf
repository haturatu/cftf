resource "cloudflare_zone" "managed" {
  for_each = nonsensitive(toset(keys(var.zones)))

  account             = { id = var.account_id }
  name                = var.zones[each.key].name
  type                = var.zones[each.key].type
  paused              = var.zones[each.key].paused
  vanity_name_servers = var.zones[each.key].vanity_name_servers

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_zone_setting" "managed" {
  for_each = nonsensitive(toset(keys(var.zone_settings)))

  zone_id    = cloudflare_zone.managed[var.zone_settings[each.key].zone_key].id
  setting_id = var.zone_settings[each.key].setting_id
  value      = var.zone_settings[each.key].value
}

resource "cloudflare_dns_record" "managed" {
  for_each = nonsensitive(toset(keys(var.dns_records)))

  zone_id         = cloudflare_zone.managed[var.dns_records[each.key].zone_key].id
  name            = var.dns_records[each.key].name
  type            = var.dns_records[each.key].type
  ttl             = var.dns_records[each.key].ttl
  content         = var.dns_records[each.key].content
  proxied         = var.dns_records[each.key].proxied
  priority        = var.dns_records[each.key].priority
  comment         = var.dns_records[each.key].comment
  tags            = var.dns_records[each.key].tags
  settings        = var.dns_records[each.key].settings
  data            = var.dns_records[each.key].data
  private_routing = var.dns_records[each.key].private_routing

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_ruleset" "managed" {
  for_each = nonsensitive(toset(keys(var.rulesets)))

  zone_id     = cloudflare_zone.managed[var.rulesets[each.key].zone_key].id
  name        = var.rulesets[each.key].name
  description = var.rulesets[each.key].description
  kind        = var.rulesets[each.key].kind
  phase       = var.rulesets[each.key].phase
  rules       = var.rulesets[each.key].rules
}
