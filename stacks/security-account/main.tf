module "security_account" {
  source = "../../modules/account-security"

  account_id        = var.account_id
  ip_lists          = var.ip_lists
  turnstile_widgets = var.turnstile_widgets
}
