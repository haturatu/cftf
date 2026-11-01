mock_provider "cloudflare" {}

variables {
  account_id        = "00000000000000000000000000000000"
  ip_lists          = {}
  turnstile_widgets = {}
}

run "accept_empty_account_security" {
  command = plan
}

run "accept_valid_ip_list_and_turnstile" {
  command = plan
  variables {
    ip_lists = {
      allow = {
        name  = "allowed_ips"
        items = [{ ip = "192.0.2.0/24" }, { ip = "2001:db8::/32" }]
      }
    }
    turnstile_widgets = {
      login = {
        name    = "login"
        domains = ["example.invalid"]
        mode    = "managed"
      }
    }
  }
}

run "accept_existing_ip_list_import_without_items" {
  command = plan
  variables {
    ip_lists = {
      existing = {
        import_id = "22222222222222222222222222222222"
        name      = "existing_ips"
      }
    }
  }
}

run "reject_more_than_one_ip_list" {
  command = plan
  variables {
    ip_lists = {
      first  = { name = "first" }
      second = { name = "second" }
    }
  }
  expect_failures = [var.ip_lists]
}

run "reject_invalid_ip_list_name" {
  command = plan
  variables {
    ip_lists = {
      invalid = { name = "not a valid name" }
    }
  }
  expect_failures = [var.ip_lists]
}

run "reject_uppercase_ip_list_name" {
  command = plan
  variables {
    ip_lists = {
      invalid = { name = "Uppercase" }
    }
  }
  expect_failures = [var.ip_lists]
}

run "reject_too_long_ip_list_name" {
  command = plan
  variables {
    ip_lists = {
      invalid = { name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    }
  }
  expect_failures = [var.ip_lists]
}

run "reject_invalid_ip_address" {
  command = plan
  variables {
    ip_lists = {
      invalid = {
        name  = "invalid_ips"
        items = [{ ip = "999.999.999.999" }]
      }
    }
  }
  expect_failures = [var.ip_lists]
}

run "reject_more_than_ten_thousand_ip_list_items" {
  command = plan
  variables {
    ip_lists = {
      too_large = {
        name = "too_large"
        items = flatten([
          for third in range(101) : [
            for fourth in range(100) : {
              ip = "10.${third}.${fourth}.1"
            }
          ]
        ])
      }
    }
  }
  expect_failures = [var.ip_lists]
}

run "reject_invalid_turnstile_mode" {
  command = plan
  variables {
    turnstile_widgets = {
      invalid = {
        name    = "invalid"
        domains = ["example.invalid"]
        mode    = "always"
      }
    }
  }
  expect_failures = [var.turnstile_widgets]
}

run "reject_empty_turnstile_domains" {
  command = plan
  variables {
    turnstile_widgets = {
      invalid = {
        name    = "invalid"
        domains = []
        mode    = "managed"
      }
    }
  }
  expect_failures = [var.turnstile_widgets]
}
