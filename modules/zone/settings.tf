resource "cloudflare_zone_setting" "managed" {
  for_each   = var.settings
  zone_id    = cloudflare_zone.managed.id
  setting_id = each.value.setting_id
  value      = try(jsondecode(each.value.value_json), null)
}
