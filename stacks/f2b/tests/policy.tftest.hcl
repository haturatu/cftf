mock_provider "cloudflare" {}
run "free_api_is_separate_from_protected_ingestion" {
  variables {
    account_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    zone_id      = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    api_hostname = "api.example.com"
    workers = {
      api    = { name = "test-api", hostname = "api.example.com" }
      ingest = { name = "test-ingest", hostname = "ingest.example.com" }
    }
    sources = {
      source_one = { jails = ["sshd", "postfix"] }
      source_two = { jails = ["sshd"] }
    }
  }
  assert {
    condition     = cloudflare_zero_trust_access_application.ingest.domain == "ingest.example.com" && cloudflare_zero_trust_access_application.ingest.policies[0].decision == "non_identity"
    error_message = "Only ingestion is protected using a Service Auth policy."
  }
  assert {
    condition     = length(cloudflare_zero_trust_access_application.source) == 2 && alltrue([for application in cloudflare_zero_trust_access_application.source : length(application.policies[0].include) == 1 && application.policies[0].decision == "non_identity"])
    error_message = "Each source path must allow only its assigned service token."
  }
  assert {
    condition     = cloudflare_workers_custom_domain.managed["api"].service == "test-api" && cloudflare_workers_custom_domain.managed["ingest"].service == "test-ingest"
    error_message = "Custom domains must reference the application-owned Worker names."
  }
  assert {
    condition     = cloudflare_workers_custom_domain.api[0].hostname == "api.example.com" && cloudflare_workers_custom_domain.api[0].service == "test-api"
    error_message = "Attach the optional API hostname to the same application Worker."
  }
  assert {
    condition     = strcontains(cloudflare_ruleset.api_browser_checks[0].rules[0].expression, "api.example.com")
    error_message = "Skip Browser Integrity Check on the dedicated API hostname."
  }
  assert {
    condition     = output.deployment_config.api_hostname == "api.example.com" && output.deployment_config.site_hostname == "api.example.com"
    error_message = "Expose the site and API hostnames through the private deployment output."
  }
  assert {
    condition     = length(output.deployment_config.source_scopes) == 2
    error_message = "Expose each Access audience only through the private deployment output."
  }
  assert {
    condition     = length(cloudflare_ruleset.api_browser_checks) == 1
    error_message = "Keep the API BIC skip rule owned by this stack until the zone stack imports it."
  }
}
