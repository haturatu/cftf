resource "cloudflare_ruleset" "managed" {
  for_each    = var.rulesets
  zone_id     = cloudflare_zone.managed.id
  name        = each.value.name
  description = each.value.description
  kind        = each.value.kind
  phase       = each.value.phase
  rules       = try(jsondecode(each.value.rules_json), null)
}
