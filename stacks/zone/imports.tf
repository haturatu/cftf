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
  for_each = { for name, ruleset in var.rulesets : name => ruleset if ruleset.id != null }
  to       = module.zone.cloudflare_ruleset.managed[each.key]
  id       = "zones/${var.zone.id}/${each.value.id}"
}
import {
  for_each = { for name, ruleset in var.managed_entrypoints : name => ruleset if ruleset.id != null }
  to       = module.zone.cloudflare_ruleset.managed_entrypoint[each.key]
  id       = "zones/${var.zone.id}/${each.value.id}"
}
import {
  for_each = var.bot_management == null ? {} : { managed = true }
  to       = module.zone.cloudflare_bot_management.managed[0]
  id       = var.zone.id
}
import {
  for_each = var.url_normalization == null ? {} : { managed = true }
  to       = module.zone.cloudflare_url_normalization_settings.managed[0]
  id       = var.zone.id
}
import {
  for_each = var.dnssec == null ? {} : { managed = true }
  to       = module.zone.cloudflare_zone_dnssec.managed[0]
  id       = var.zone.id
}
import {
  for_each = var.managed_transforms == null ? {} : { managed = true }
  to       = module.zone.cloudflare_managed_transforms.managed[0]
  id       = var.zone.id
}
import {
  for_each = var.leaked_credential_check == null ? {} : { managed = true }
  to       = module.zone.cloudflare_leaked_credential_check.managed[0]
  id       = var.zone.id
}
import {
  for_each = var.authenticated_origin_pulls == null ? {} : { managed = true }
  to       = module.zone.cloudflare_authenticated_origin_pulls_settings.managed[0]
  id       = var.zone.id
}
import {
  for_each = { for name, rule in var.access_rules : name => rule if rule.id != null }
  to       = module.zone.cloudflare_access_rule.managed[each.key]
  id       = "zones/${var.zone.id}/${each.value.id}"
}
import {
  for_each = { for name, rule in var.user_agent_blocking_rules : name => rule if rule.id != null }
  to       = module.zone.cloudflare_user_agent_blocking_rule.managed[each.key]
  id       = "${var.zone.id}/${each.value.id}"
}
