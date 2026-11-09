output "dnssec_ds" {
  description = "DS record to publish at the registrar after enabling DNSSEC."
  value       = try(cloudflare_zone_dnssec.managed[0].ds, null)
  sensitive   = true
}

output "dnssec_status" {
  description = "Cloudflare DNSSEC status after the last apply."
  value       = try(cloudflare_zone_dnssec.managed[0].status, null)
}

output "origin_ca_certificates" {
  description = "Issued Origin CA certificates. Private keys are never managed by Terraform."
  value = {
    for name, certificate in cloudflare_origin_ca_certificate.managed : name => {
      id          = certificate.id
      certificate = certificate.certificate
      expires_on  = certificate.expires_on
    }
  }
  sensitive = true
}
