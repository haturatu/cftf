resource "cloudflare_zone" "managed" {
  account             = { id = var.account_id }
  name                = var.zone.name
  type                = var.zone.type
  paused              = var.zone.paused
  vanity_name_servers = var.zone.vanity_name_servers
  lifecycle { prevent_destroy = true }
}
