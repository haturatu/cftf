resource "cloudflare_r2_bucket" "state" {
  account_id   = var.account_id
  name         = var.bucket_name
  location     = var.location
  jurisdiction = var.jurisdiction
  lifecycle { prevent_destroy = true }
}

resource "cloudflare_r2_managed_domain" "state" {
  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.state.name
  jurisdiction = var.jurisdiction
  enabled      = var.public_access_enabled
}
