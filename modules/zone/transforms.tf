resource "cloudflare_managed_transforms" "managed" {
  count   = var.managed_transforms == null ? 0 : 1
  zone_id = cloudflare_zone.managed.id

  managed_request_headers  = length(var.managed_transforms.request_headers) > 0 ? var.managed_transforms.request_headers : null
  managed_response_headers = length(var.managed_transforms.response_headers) > 0 ? var.managed_transforms.response_headers : null
}
