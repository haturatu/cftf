module "zone" {
  source      = "../../../../modules/zone"
  account_id  = var.account_id
  zone        = var.zone
  dns_records = var.dns_records
  settings    = var.settings
  rulesets    = var.rulesets
}
