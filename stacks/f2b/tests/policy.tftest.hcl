mock_provider "cloudflare" {}
run "free_api_is_separate_from_protected_ingestion" {
  variables {
    account_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    zone_id    = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    workers = {
      api    = { name = "test-api", hostname = "api.example.com", source_path = "tests/fixtures/worker.js" }
      ingest = { name = "test-ingest", hostname = "ingest.example.com", source_path = "tests/fixtures/worker.js" }
    }
    sources = {
      source_one = { jails = ["sshd", "postfix"] }
      source_two = { jails = ["sshd"] }
    }
  }
  assert {
    condition     = length(cloudflare_workers_script.managed) == 2 && length(cloudflare_zero_trust_access_service_token.source) == 2
    error_message = "Use two Workers and independent collection credentials."
  }
  assert {
    condition     = alltrue([for subdomain in cloudflare_workers_script_subdomain.disabled : !subdomain.enabled && !subdomain.previews_enabled])
    error_message = "Alternate unprotected endpoints must stay disabled."
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
    condition     = alltrue([for worker in cloudflare_workers_script.managed : worker.usage_model == "standard"])
    error_message = "Avoid container and paid compute resources."
  }
}
