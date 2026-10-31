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
