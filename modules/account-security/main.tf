resource "cloudflare_list" "managed" {
  for_each = var.ip_lists

  account_id  = var.account_id
  kind        = "ip"
  name        = each.value.name
  description = each.value.description
  items = each.value.items == null ? null : [
    for item in each.value.items : {
      ip      = item.ip
      comment = item.comment
    }
  ]
}

resource "cloudflare_turnstile_widget" "managed" {
  for_each = var.turnstile_widgets

  account_id      = var.account_id
  name            = each.value.name
  domains         = each.value.domains
  mode            = each.value.mode
  clearance_level = try(each.value.clearance_level, null)
  region          = each.value.region
}
