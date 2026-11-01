data "cloudflare_rulesets" "existing" {
  count   = length(var.rulesets) + length(var.managed_entrypoints) > 0 ? 1 : 0
  zone_id = var.zone.id
}
