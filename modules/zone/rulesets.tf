resource "cloudflare_ruleset" "managed" {
  for_each    = var.rulesets
  zone_id     = cloudflare_zone.managed.id
  name        = each.value.name
  description = each.value.description
  kind        = each.value.kind
  phase       = each.value.phase
  rules       = try(jsondecode(each.value.rules_json), null)
}

# Cloudflare creates managed rulesets automatically. This resource only manages
# overrides after the existing entrypoint ruleset has been imported by id.
resource "cloudflare_ruleset" "managed_override" {
  for_each    = var.managed_rulesets
  zone_id     = cloudflare_zone.managed.id
  name        = each.value.name
  description = each.value.description
  kind        = "managed"
  phase       = each.value.phase
  rules       = try(jsondecode(each.value.rules_json), null)
  lifecycle { prevent_destroy = true }
}
