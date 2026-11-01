locals {
  web_baseline_settings = var.web_baseline == null ? {} : {
    ssl = {
      setting_id = "ssl"
      value_json = jsonencode("strict")
    }
    always_use_https = {
      setting_id = "always_use_https"
      value_json = jsonencode("on")
    }
    min_tls_version = {
      setting_id = "min_tls_version"
      value_json = jsonencode("1.2")
    }
    tls_1_3 = {
      setting_id = "tls_1_3"
      value_json = jsonencode("on")
    }
    browser_check = {
      setting_id = "browser_check"
      value_json = jsonencode("on")
    }
  }

  managed_settings = merge(var.settings, local.web_baseline_settings)
  managed_url_normalization = (
    var.web_baseline != null && var.web_baseline.url_normalization
    ? { scope = "incoming", type = "rfc3986" }
    : var.url_normalization
  )
  managed_dnssec = (
    var.web_baseline != null && var.web_baseline.dnssec
    ? { status = "active" }
    : var.dnssec
  )
}
