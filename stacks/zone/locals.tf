locals {
  web_baseline_values = {
    ssl              = "strict"
    always_use_https = "on"
    min_tls_version  = "1.2"
    tls_1_3          = "on"
    browser_check    = "on"
  }

  # Reuse the existing map key when the setting is already managed. This keeps
  # import addresses stable and avoids duplicate setting_id validation errors.
  web_baseline_settings = var.web_baseline == null ? {} : {
    for setting_id, value in local.web_baseline_values :
    try(
      [for key, setting in var.settings : key if setting.setting_id == setting_id][0],
      "baseline_${setting_id}"
      ) => {
      setting_id = setting_id
      value_json = jsonencode(value)
    }
  }

  filtered_settings = {
    for key, setting in var.settings : key => setting
    if var.web_baseline == null || !contains(keys(local.web_baseline_values), setting.setting_id)
  }

  managed_settings = merge(local.filtered_settings, local.web_baseline_settings)
  managed_url_normalization = (
    var.web_baseline != null && var.web_baseline.url_normalization
    ? { scope = "incoming", type = "cloudflare" }
    : var.url_normalization
  )
  managed_dnssec = (
    var.web_baseline != null && var.web_baseline.dnssec
    ? { status = "active" }
    : var.dnssec
  )
}
