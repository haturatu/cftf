variable "account_id" {
  description = "Cloudflare account identifier supplied by the private configuration."
  type        = string

  nullable = false
}

variable "zones" {
  description = "Existing zones indexed by stable, non-identifying local aliases."
  type = map(object({
    id                  = string
    name                = string
    type                = string
    paused              = bool
    vanity_name_servers = optional(list(string))
  }))

  nullable = false
}

variable "zone_settings" {
  description = "Zone settings keyed by local aliases. Values retain their API-specific types."
  type        = any

  nullable = false
}

variable "dns_records" {
  description = "DNS records including their private import identifiers and actual record values."
  type = map(object({
    id              = string
    zone_key        = string
    name            = string
    type            = string
    ttl             = number
    content         = optional(string)
    proxied         = optional(bool)
    priority        = optional(number)
    comment         = optional(string)
    tags            = optional(set(string))
    settings        = optional(any)
    data            = optional(any)
    private_routing = optional(bool)
  }))

  nullable = false
}

variable "buckets" {
  description = "R2 bucket properties, public access, lifecycle and optional CORS configuration."
  type        = any

  nullable = false
}

variable "workers" {
  description = "Worker settings and paths to private source files; secret values are excluded."
  type        = any

  nullable = false
}

variable "worker_crons" {
  description = "Worker cron schedules supplied only by the private configuration."
  type = map(object({
    worker_key = string
    schedules  = list(object({ cron = string }))
  }))

  nullable = false
}

variable "worker_routes" {
  description = "Existing zone routes indexed by local aliases."
  type = map(object({
    id       = string
    zone_key = string
    pattern  = string
    script   = optional(string)
  }))

  nullable = false
}

variable "worker_domains" {
  description = "Existing Worker custom domains indexed by local aliases."
  type = map(object({
    id          = string
    hostname    = string
    service     = string
    environment = optional(string)
    zone_id     = string
  }))

  nullable = false
}

variable "rulesets" {
  description = "User-owned zone rulesets; Cloudflare-managed definitions are excluded."
  type        = any

  nullable = false
}
