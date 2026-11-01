mock_provider "cloudflare" {}

override_resource {
  target = module.zone.cloudflare_zone.managed
  values = {
    id = "11111111111111111111111111111111"
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
  settings    = {}
  rulesets = {
    global_rate_limit = {
      name        = "Global HTTP Rate Limit"
      description = "IP-based limit for all HTTP traffic"
      kind        = "zone"
      phase       = "http_ratelimit"
      rules_json = jsonencode([{
        ref         = "global_ip_rate_limit"
        description = "Limit all HTTP requests per IP"
        action      = "block"
        expression  = "true"
        enabled     = true
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

run "create_global_rate_limit" {
  command = plan
}
