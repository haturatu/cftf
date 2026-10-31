import {
  to = module.zone.cloudflare_zone.managed
  id = var.zone.id
}
import {
  for_each = var.settings
  to       = module.zone.cloudflare_zone_setting.managed[each.key]
  id       = "${var.zone.id}/${each.value.setting_id}"
}
import {
  for_each = var.dns_records
  to       = module.zone.cloudflare_dns_record.managed[each.key]
  id       = "${var.zone.id}/${each.value.id}"
}
import {
  for_each = var.rulesets
  to       = module.zone.cloudflare_ruleset.managed[each.key]
  id       = "${var.zone.id}/${each.value.id}"
}
