import {
  for_each = nonsensitive(toset(keys(var.zones)))
  to       = cloudflare_zone.managed[each.key]
  id       = var.zones[each.key].id
}

import {
  for_each = nonsensitive(toset(keys(var.zone_settings)))
  to       = cloudflare_zone_setting.managed[each.key]
  id       = "${var.zones[var.zone_settings[each.key].zone_key].id}/${var.zone_settings[each.key].setting_id}"
}

import {
  for_each = nonsensitive(toset(keys(var.dns_records)))
  to       = cloudflare_dns_record.managed[each.key]
  id       = "${var.zones[var.dns_records[each.key].zone_key].id}/${var.dns_records[each.key].id}"
}

import {
  for_each = nonsensitive(toset(keys(var.buckets)))
  to       = cloudflare_r2_bucket.managed[each.key]
  id       = "${var.account_id}/${var.buckets[each.key].name}/${var.buckets[each.key].jurisdiction}"
}

import {
  for_each = nonsensitive(toset(keys(var.workers)))
  to       = cloudflare_workers_script.managed[each.key]
  id       = "${var.account_id}/${var.workers[each.key].name}"
}

import {
  for_each = nonsensitive(toset(keys(var.worker_crons)))
  to       = cloudflare_workers_cron_trigger.managed[each.key]
  id       = "${var.account_id}/${var.workers[var.worker_crons[each.key].worker_key].name}"
}

import {
  for_each = nonsensitive(toset(keys(var.worker_routes)))
  to       = cloudflare_workers_route.managed[each.key]
  id       = "${var.zones[var.worker_routes[each.key].zone_key].id}/${var.worker_routes[each.key].id}"
}

import {
  for_each = nonsensitive(toset(keys(var.worker_domains)))
  to       = cloudflare_workers_custom_domain.managed[each.key]
  id       = "${var.account_id}/${var.worker_domains[each.key].id}"
}

import {
  for_each = nonsensitive(toset(keys(var.workers)))
  to       = cloudflare_workers_script_subdomain.managed[each.key]
  id       = "${var.account_id}/${var.workers[each.key].name}"
}

import {
  for_each = nonsensitive(toset(keys(var.rulesets)))
  to       = cloudflare_ruleset.managed[each.key]
  id       = "zone/${var.zones[var.rulesets[each.key].zone_key].id}/${var.rulesets[each.key].id}"
}
