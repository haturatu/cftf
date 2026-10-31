resource "cloudflare_r2_bucket" "managed" {
  for_each = nonsensitive(toset(keys(var.buckets)))

  account_id    = var.account_id
  name          = var.buckets[each.key].name
  location      = var.buckets[each.key].location
  jurisdiction  = var.buckets[each.key].jurisdiction
  storage_class = var.buckets[each.key].storage_class

  lifecycle {
    prevent_destroy = true
  }
}

# These settings endpoints have no importer in the pinned provider version.
# Their first apply adopts the captured settings through idempotent API writes.
resource "cloudflare_r2_managed_domain" "managed" {
  for_each = nonsensitive(toset(keys(var.buckets)))

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.managed[each.key].name
  jurisdiction = var.buckets[each.key].jurisdiction
  enabled      = var.buckets[each.key].public_access_enabled
}

resource "cloudflare_r2_bucket_lifecycle" "managed" {
  for_each = nonsensitive(toset(keys(var.buckets)))

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.managed[each.key].name
  jurisdiction = var.buckets[each.key].jurisdiction
  rules        = var.buckets[each.key].lifecycle_rules
}

resource "cloudflare_r2_bucket_cors" "managed" {
  for_each = nonsensitive(toset([
    for key, bucket in var.buckets : key if bucket.cors_rules != null
  ]))

  account_id   = var.account_id
  bucket_name  = cloudflare_r2_bucket.managed[each.key].name
  jurisdiction = var.buckets[each.key].jurisdiction
  rules        = var.buckets[each.key].cors_rules
}
