resource "cloudflare_ruleset" "managed" {
  for_each    = var.rulesets
  zone_id     = cloudflare_zone.managed.id
  name        = each.value.name
  description = each.value.description
  kind        = each.value.kind
  phase       = each.value.phase
  rules       = try(jsondecode(each.value.rules_json), null)

  lifecycle {
    precondition {
      condition     = each.value.id != null || !contains(var.existing_zone_ruleset_phases, each.value.phase)
      error_message = "A zone entrypoint ruleset already exists for phase ${each.value.phase}. Import its existing id instead of creating a duplicate."
    }
  }
}

# Cloudflare creates managed rulesets automatically. To deploy or override one,
# manage the zone phase entrypoint (kind = "zone") with execute rules that
# reference the managed ruleset id. The id here is the entrypoint ruleset id.
resource "cloudflare_ruleset" "managed_entrypoint" {
  for_each    = var.managed_entrypoints
  zone_id     = cloudflare_zone.managed.id
  name        = each.value.name
  description = each.value.description
  kind        = "zone"
  phase       = each.value.phase
  rules       = try(jsondecode(each.value.rules_json), null)

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = each.value.id != null || !contains(var.existing_zone_ruleset_phases, each.value.phase)
      error_message = "A zone entrypoint ruleset already exists for phase ${each.value.phase}. Import its existing id instead of creating a duplicate."
    }
  }
}
