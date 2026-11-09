output "dnssec_ds" {
  description = "DS record to publish at the registrar after enabling DNSSEC."
  value       = module.zone.dnssec_ds
  sensitive   = true
}

output "dnssec_status" {
  description = "Cloudflare DNSSEC status after the last apply."
  value       = module.zone.dnssec_status
}

output "origin_ca_certificates" {
  description = "Issued Origin CA certificates for installation on the origin."
  value       = module.zone.origin_ca_certificates
  sensitive   = true
}
