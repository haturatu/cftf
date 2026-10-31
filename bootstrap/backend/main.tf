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

resource "cloudflare_r2_bucket" "config" {
  account_id   = var.account_id
  name         = var.config_bucket.name
  location     = var.config_bucket.location
  jurisdiction = var.config_bucket.jurisdiction

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_r2_managed_domain" "config" {
  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.config.name
  jurisdiction = var.config_bucket.jurisdiction
  enabled      = var.config_bucket.public_access_enabled
}
