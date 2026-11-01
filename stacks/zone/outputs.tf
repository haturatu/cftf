output "dnssec_ds" {
  description = "DS record to publish at the registrar after enabling DNSSEC."
  value       = module.zone.dnssec_ds
  sensitive   = true
}

output "dnssec_status" {
  description = "Cloudflare DNSSEC status after the last apply."
  value       = module.zone.dnssec_status
}
