mock_provider "cloudflare" {}

override_resource {
  target = module.zone.cloudflare_zone.managed
  values = {
    id = "11111111111111111111111111111111"
  }
}

override_resource {
  target = module.zone.cloudflare_zone_setting.managed["ssl"]
  values = {
    id         = "ssl"
    setting_id = "ssl"
    zone_id    = "11111111111111111111111111111111"
    value      = "strict"
  }
}

override_resource {
  target = module.zone.cloudflare_zone_setting.managed["always_use_https"]
  values = {
    id         = "always_use_https"
    setting_id = "always_use_https"
    zone_id    = "11111111111111111111111111111111"
    value      = "on"
  }
}

override_resource {
  target = module.zone.cloudflare_zone_setting.managed["min_tls_version"]
  values = {
    id         = "min_tls_version"
    setting_id = "min_tls_version"
    zone_id    = "11111111111111111111111111111111"
    value      = "1.2"
  }
}

override_resource {
  target = module.zone.cloudflare_zone_setting.managed["tls_1_3"]
  values = {
    id         = "tls_1_3"
    setting_id = "tls_1_3"
    zone_id    = "11111111111111111111111111111111"
    value      = "on"
  }
}

override_resource {
  target = module.zone.cloudflare_zone_setting.managed["browser_check"]
  values = {
    id         = "browser_check"
    setting_id = "browser_check"
    zone_id    = "11111111111111111111111111111111"
    value      = "on"
  }
}

override_resource {
  target = module.zone.cloudflare_zone_setting.managed["hotlink_protection"]
  values = {
    id         = "hotlink_protection"
    setting_id = "hotlink_protection"
    zone_id    = "11111111111111111111111111111111"
    value      = "off"
  }
}

override_resource {
  target = module.zone.cloudflare_url_normalization_settings.managed[0]
  values = {
    id      = "11111111111111111111111111111111"
    zone_id = "11111111111111111111111111111111"
    scope   = "incoming"
    type    = "rfc3986"
  }
}

variables {
  account_id = "00000000000000000000000000000000"
  zone = {
    id     = "11111111111111111111111111111111"
    name   = "example.invalid"
    type   = "full"
    paused = false
  }
  dns_records = {}
  settings = {
    ssl = {
      setting_id = "ssl"
      value_json = jsonencode("full")
    }
    always_use_https = {
      setting_id = "always_use_https"
      value_json = jsonencode("off")
    }
    min_tls_version = {
      setting_id = "min_tls_version"
      value_json = jsonencode("1.0")
    }
    tls_1_3 = {
      setting_id = "tls_1_3"
      value_json = jsonencode("off")
    }
    browser_check = {
      setting_id = "browser_check"
      value_json = jsonencode("off")
    }
    hotlink_protection = {
      setting_id = "hotlink_protection"
      value_json = jsonencode("off")
    }
  }
  rulesets = {}
  web_baseline = {
    url_normalization = true
    dnssec            = false
  }
}

run "apply_web_baseline" {
  command = plan

  assert {
    condition = (
      local.managed_settings["ssl"].value_json == jsonencode("strict") &&
      local.managed_settings["always_use_https"].value_json == jsonencode("on") &&
      local.managed_settings["min_tls_version"].value_json == jsonencode("1.2") &&
      local.managed_settings["tls_1_3"].value_json == jsonencode("on") &&
      local.managed_settings["browser_check"].value_json == jsonencode("on")
    )
    error_message = "The web baseline must enforce Full (strict), HTTPS, TLS 1.2, TLS 1.3, and Browser Integrity Check."
  }

  assert {
    condition     = local.managed_settings["hotlink_protection"].value_json == jsonencode("off")
    error_message = "Settings outside the baseline must be preserved."
  }

  assert {
    condition     = local.managed_url_normalization.scope == "incoming" && local.managed_url_normalization.type == "rfc3986"
    error_message = "The web baseline must normalize incoming URLs before WAF evaluation."
  }

  assert {
    condition     = local.managed_dnssec == null
    error_message = "DNSSEC must remain disabled unless explicitly requested."
  }
}
