import {
  for_each = var.workers
  to       = cloudflare_workers_script.managed[each.key]
  id       = "${var.account_id}/${each.value.name}"
}
import {
  for_each = var.worker_crons
  to       = cloudflare_workers_cron_trigger.managed[each.key]
  id       = "${var.account_id}/${var.workers[each.value.worker_key].name}"
}
import {
  for_each = var.worker_routes
  to       = cloudflare_workers_route.managed[each.key]
  id       = "${each.value.zone_id}/${each.value.id}"
}
import {
  for_each = var.worker_domains
  to       = cloudflare_workers_custom_domain.managed[each.key]
  id       = "${var.account_id}/${each.value.id}"
}
import {
  for_each = var.workers
  to       = cloudflare_workers_script_subdomain.managed[each.key]
  id       = "${var.account_id}/${each.value.name}"
}
