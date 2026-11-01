mock_provider "cloudflare" {}

variables {
  account_id = "00000000000000000000000000000000"
  zone = {
    id     = "11111111111111111111111111111111"
    name   = "example.invalid"
    type   = "full"
    paused = false
  }
  dns_records = {}
  settings    = {}
  rulesets    = {}
}

run "accept_valid_zone" {
  command = plan
}

run "reject_invalid_account_id" {
  command = plan
  variables {
    account_id = "invalid"
  }
  expect_failures = [var.account_id]
}

run "reject_invalid_zone_id" {
  command = plan
  variables {
    zone = {
      id     = "invalid"
      name   = "example.invalid"
      type   = "full"
      paused = false
    }
  }
  expect_failures = [var.zone]
}

run "reject_invalid_dns_ttl" {
  command = plan
  variables {
    dns_records = {
      sample = {
        id      = "22222222222222222222222222222222"
        name    = "example.invalid"
        type    = "A"
        content = "192.0.2.1"
        ttl     = -1
      }
    }
  }
  expect_failures = [var.dns_records]
}

run "reject_invalid_setting_json" {
  command = plan
  variables {
    settings = {
      sample = {
        setting_id = "example"
        value_json = "{"
      }
    }
  }
  expect_failures = [var.settings]
}

run "reject_duplicate_setting_ownership" {
  command = plan
  variables {
    settings = {
      first = {
        setting_id = "example"
        value_json = "true"
      }
      second = {
        setting_id = "example"
        value_json = "false"
      }
    }
  }
  expect_failures = [var.settings]
}

run "accept_free_plan_security_controls" {
  command = plan
  variables {
    bot_management = {
      fight_mode            = true
      ai_bots_protection    = "block"
      crawler_protection    = "enabled"
      is_robots_txt_managed = true
    }
    url_normalization = {
      scope = "incoming"
      type  = "rfc3986"
    }
    dnssec = {
      status = "active"
    }
    managed_transforms = {
      response_headers = [
        { id = "add_security_headers", enabled = true },
        { id = "remove_x-powered-by_header", enabled = true },
      ]
    }
    leaked_credential_check    = true
    authenticated_origin_pulls = false
    access_rules = {
      block_bad_ip = {
        mode   = "block"
        target = "ip"
        value  = "192.0.2.1"
      }
    }
    user_agent_blocking_rules = {
      block_bad_agent = {
        mode  = "block"
        value = "BadBot/1.0"
      }
    }
  }
}

run "reject_duplicate_ruleset_phase" {
  command = plan
  variables {
    rulesets = {
      first = {
        name       = "first"
        kind       = "zone"
        phase      = "http_request_firewall_custom"
        rules_json = jsonencode([])
      }
      second = {
        name       = "second"
        kind       = "zone"
        phase      = "http_request_firewall_custom"
        rules_json = jsonencode([])
      }
    }
  }
  expect_failures = [var.rulesets]
}

run "reject_more_than_five_custom_waf_rules" {
  command = plan
  variables {
    rulesets = {
      custom = {
        name  = "custom"
        kind  = "zone"
        phase = "http_request_firewall_custom"
        rules_json = jsonencode([
          for index in range(6) : {
            action     = "block"
            expression = "http.request.uri.path eq \"/${index}\""
          }
        ])
      }
    }
  }
  expect_failures = [var.rulesets]
}

run "accept_free_plan_rate_limit" {
  command = plan
  variables {
    rulesets = {
      limit = {
        name  = "limit"
        kind  = "zone"
        phase = "http_ratelimit"
        rules_json = jsonencode([{
          action     = "block"
          expression = "starts_with(http.request.uri.path, \"/api/\")"
          ratelimit = {
            characteristics     = ["cf.colo.id", "ip.src"]
            period              = 10
            requests_per_period = 30
            mitigation_timeout  = 10
          }
        }])
      }
    }
  }
}

run "accept_free_plan_challenge_rate_limit" {
  command = plan
  variables {
    rulesets = {
      limit = {
        name  = "limit"
        kind  = "zone"
        phase = "http_ratelimit"
        rules_json = jsonencode([{
          action     = "managed_challenge"
          expression = "starts_with(http.request.uri.path, \"/login/\")"
          ratelimit = {
            characteristics     = ["cf.colo.id", "ip.src"]
            period              = 10
            requests_per_period = 20
            mitigation_timeout  = 0
          }
        }])
      }
    }
  }
}

run "reject_rate_limit_without_cf_colo_id" {
  command = plan
  variables {
    rulesets = {
      limit = {
        name  = "limit"
        kind  = "zone"
        phase = "http_ratelimit"
        rules_json = jsonencode([{
          action     = "block"
          expression = "starts_with(http.request.uri.path, \"/api/\")"
          ratelimit = {
            characteristics     = ["ip.src"]
            period              = 10
            requests_per_period = 30
            mitigation_timeout  = 10
          }
        }])
      }
    }
  }
  expect_failures = [var.rulesets]
}

run "reject_challenge_rate_limit_with_duration" {
  command = plan
  variables {
    rulesets = {
      limit = {
        name  = "limit"
        kind  = "zone"
        phase = "http_ratelimit"
        rules_json = jsonencode([{
          action     = "managed_challenge"
          expression = "starts_with(http.request.uri.path, \"/login/\")"
          ratelimit = {
            characteristics     = ["cf.colo.id", "ip.src"]
            period              = 10
            requests_per_period = 20
            mitigation_timeout  = 10
          }
        }])
      }
    }
  }
  expect_failures = [var.rulesets]
}

run "reject_free_plan_rate_limit_period" {
  command = plan
  variables {
    rulesets = {
      limit = {
        name  = "limit"
        kind  = "zone"
        phase = "http_ratelimit"
        rules_json = jsonencode([{
          action     = "block"
          expression = "starts_with(http.request.uri.path, \"/api/\")"
          ratelimit = {
            characteristics     = ["cf.colo.id", "ip.src"]
            period              = 60
            requests_per_period = 100
            mitigation_timeout  = 60
          }
        }])
      }
    }
  }
  expect_failures = [var.rulesets]
}

run "reject_more_than_ten_user_agent_rules" {
  command = plan
  variables {
    user_agent_blocking_rules = {
      for index in range(11) : "rule_${index}" => {
        mode  = "block"
        value = "BadBot/${index}"
      }
    }
  }
  expect_failures = [var.user_agent_blocking_rules]
}

run "reject_invalid_bot_management_value" {
  command = plan
  variables {
    bot_management = {
      ai_bots_protection = "allow"
    }
  }
  expect_failures = [var.bot_management]
}

run "reject_invalid_url_normalization_scope" {
  command = plan
  variables {
    url_normalization = {
      scope = "egress"
      type  = "rfc3986"
    }
  }
  expect_failures = [var.url_normalization]
}

run "accept_managed_entrypoint" {
  command = plan
  variables {
    managed_entrypoints = {
      free_managed = {
        name  = "Free Managed WAF entrypoint"
        phase = "http_request_firewall_managed"
        rules_json = jsonencode([{
          action     = "execute"
          expression = "true"
          action_parameters = {
            id = "22222222222222222222222222222222"
          }
        }])
      }
    }
  }
  assert {
    condition     = cloudflare_ruleset.managed_entrypoint["free_managed"].kind == "zone"
    error_message = "Managed ruleset deployments must use the zone phase entrypoint (kind = \"zone\"), not the managed ruleset itself."
  }
}

run "reject_empty_managed_entrypoint_rules" {
  command = plan
  variables {
    managed_entrypoints = {
      free_managed = {
        name       = "Free Managed WAF entrypoint"
        phase      = "http_request_firewall_managed"
        rules_json = jsonencode([])
      }
    }
  }
  expect_failures = [var.managed_entrypoints]
}

run "reject_phase_owned_by_zone_and_managed_entrypoints" {
  command = plan
  variables {
    rulesets = {
      zone_entry = {
        name       = "zone entry"
        kind       = "zone"
        phase      = "http_request_firewall_managed"
        rules_json = jsonencode([])
      }
    }
    managed_entrypoints = {
      managed_entry = {
        name       = "managed entry"
        phase      = "http_request_firewall_managed"
        rules_json = jsonencode([])
      }
    }
  }
  expect_failures = [var.managed_entrypoints]
}

run "reject_duplicate_existing_zone_entrypoint_without_import" {
  command = plan
  variables {
    existing_zone_ruleset_phases = ["http_request_firewall_custom"]
    rulesets = {
      custom = {
        name       = "custom"
        kind       = "zone"
        phase      = "http_request_firewall_custom"
        rules_json = jsonencode([])
      }
    }
  }
  expect_failures = [cloudflare_ruleset.managed["custom"]]
}
