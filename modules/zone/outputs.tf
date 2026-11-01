output "dnssec_ds" {
  description = "DS record to publish at the registrar after enabling DNSSEC."
  value       = try(cloudflare_zone_dnssec.managed[0].ds, null)
  sensitive   = true
}

output "dnssec_status" {
  description = "Cloudflare DNSSEC status after the last apply."
  value       = try(cloudflare_zone_dnssec.managed[0].status, null)
}
