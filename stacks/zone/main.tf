module "zone" {
  source      = "../../modules/zone"
  account_id  = var.account_id
  zone        = var.zone
  dns_records = var.dns_records
  settings    = var.settings
  rulesets    = var.rulesets

  managed_rulesets           = var.managed_rulesets
  bot_management             = var.bot_management
  url_normalization          = var.url_normalization
  dnssec                     = var.dnssec
  managed_transforms         = var.managed_transforms
  leaked_credential_check    = var.leaked_credential_check
  authenticated_origin_pulls = var.authenticated_origin_pulls
  access_rules               = var.access_rules
  user_agent_blocking_rules  = var.user_agent_blocking_rules
}
