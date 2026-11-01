resource "cloudflare_bot_management" "managed" {
  count   = var.bot_management == null ? 0 : 1
  zone_id = cloudflare_zone.managed.id

  fight_mode                  = try(var.bot_management.fight_mode, null)
  ai_bots_protection          = try(var.bot_management.ai_bots_protection, null)
  ai_training                 = try(var.bot_management.ai_training, null)
  ai_user                     = try(var.bot_management.ai_user, null)
  aisearch                    = try(var.bot_management.aisearch, null)
  crawler_protection          = try(var.bot_management.crawler_protection, null)
  cf_robots_variant           = try(var.bot_management.cf_robots_variant, null)
  is_robots_txt_managed       = try(var.bot_management.is_robots_txt_managed, null)
  bot_preference_sync_enabled = try(var.bot_management.bot_preference_sync_enabled, null)
}
