module "zone" {
  source      = "../../modules/zone"
  account_id  = var.account_id
  zone        = var.zone
  dns_records = var.dns_records
  settings    = local.managed_settings
  rulesets    = var.rulesets

  managed_entrypoints = var.managed_entrypoints
  existing_zone_ruleset_phases = toset([
    for ruleset in try(data.cloudflare_rulesets.existing[0].rulesets, toset([])) : ruleset.phase
    if ruleset.kind == "zone"
  ])

  bot_management             = var.bot_management
  url_normalization          = local.managed_url_normalization
  dnssec                     = local.managed_dnssec
  managed_transforms         = var.managed_transforms
  leaked_credential_check    = var.leaked_credential_check
  authenticated_origin_pulls = var.authenticated_origin_pulls
  access_rules               = var.access_rules
  user_agent_blocking_rules  = var.user_agent_blocking_rules
}
