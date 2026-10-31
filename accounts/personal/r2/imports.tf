import {
  for_each = var.buckets
  to       = cloudflare_r2_bucket.managed[each.key]
  id       = "${var.account_id}/${each.value.name}/${each.value.jurisdiction}"
}
