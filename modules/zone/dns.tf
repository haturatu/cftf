resource "cloudflare_dns_record" "managed" {
  for_each        = var.dns_records
  zone_id         = cloudflare_zone.managed.id
  name            = each.value.name
  type            = each.value.type
  ttl             = each.value.ttl
  content         = each.value.content
  proxied         = each.value.proxied
  priority        = each.value.priority
  comment         = each.value.comment
  tags            = each.value.tags
  settings        = each.value.settings
  data            = each.value.data
  private_routing = each.value.private_routing
  lifecycle { prevent_destroy = true }
}
