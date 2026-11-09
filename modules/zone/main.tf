resource "cloudflare_zone" "managed" {
  account             = { id = var.account_id }
  name                = var.zone.name
  type                = var.zone.type
  paused              = var.zone.paused
  vanity_name_servers = var.zone.vanity_name_servers
  lifecycle { prevent_destroy = true }
}

resource "cloudflare_origin_cloud_region" "managed" {
  for_each  = var.origin_cloud_regions
  zone_id   = cloudflare_zone.managed.id
  origin_ip = each.value.origin_ip
  vendor    = each.value.vendor
  region    = each.value.region
}

resource "cloudflare_origin_ca_certificate" "managed" {
  for_each           = var.origin_ca_certificates
  csr                = each.value.csr
  hostnames          = each.value.hostnames
  request_type       = each.value.request_type
  requested_validity = each.value.requested_validity
}
