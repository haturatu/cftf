resource "cloudflare_list" "managed" {
  for_each = var.ip_lists

  account_id  = var.account_id
  kind        = "ip"
  name        = each.value.name
  description = each.value.description
  items = [
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
  bot_fight_mode  = try(each.value.bot_fight_mode, null)
  clearance_level = try(each.value.clearance_level, null)
  ephemeral_id    = try(each.value.ephemeral_id, null)
  offlabel        = try(each.value.offlabel, null)
  region          = each.value.region
}
