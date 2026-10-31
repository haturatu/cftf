mock_provider "cloudflare" {}

variables {
  account_id            = "00000000000000000000000000000000"
  bucket_name           = "example-state-bucket"
  jurisdiction          = "default"
  location              = "apac"
  public_access_enabled = false
}

run "accept_private_state_bucket" {
  command = plan
}

run "reject_public_state_bucket" {
  command = plan
  variables {
    public_access_enabled = true
  }
  expect_failures = [var.public_access_enabled]
}

run "reject_invalid_state_bucket_location" {
  command = plan
  variables {
    location = "invalid"
  }
  expect_failures = [var.location]
}
