import {
  for_each = { for name, list in var.ip_lists : name => list if list.import_id != null }
  to       = module.security_account.cloudflare_list.managed[each.key]
  id       = "${var.account_id}/${each.value.import_id}"
}
import {
  for_each = { for name, widget in var.turnstile_widgets : name => widget if widget.import_id != null }
  to       = module.security_account.cloudflare_turnstile_widget.managed[each.key]
  id       = "${var.account_id}/${each.value.import_id}"
}
