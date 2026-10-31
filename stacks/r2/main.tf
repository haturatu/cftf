resource "cloudflare_r2_bucket" "managed" {
  for_each = var.buckets

  account_id    = var.account_id
  name          = each.value.name
  location      = each.value.location
  jurisdiction  = each.value.jurisdiction
  storage_class = each.value.storage_class

  lifecycle {
    prevent_destroy = true
  }
}

# These settings endpoints have no importer in the pinned provider version.
# Their first apply adopts the captured settings through idempotent API writes.
resource "cloudflare_r2_managed_domain" "managed" {
  for_each = var.buckets

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.managed[each.key].name
  jurisdiction = each.value.jurisdiction
  enabled      = each.value.public_access_enabled
}

resource "cloudflare_r2_bucket_lifecycle" "managed" {
  for_each = var.buckets

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.managed[each.key].name
  jurisdiction = each.value.jurisdiction
  rules        = each.value.lifecycle_rules
}

resource "cloudflare_r2_bucket_cors" "managed" {
  for_each = { for key, bucket in var.buckets : key => bucket if bucket.cors_rules != null }

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.managed[each.key].name
  jurisdiction = each.value.jurisdiction
  rules        = each.value.cors_rules
}
