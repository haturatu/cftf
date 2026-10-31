variable "account_id" {
  description = "Cloudflare account identifier supplied privately."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal identifier."
  }
}

variable "dns_records" {
  description = "Existing DNS records belonging to this zone."
  type = map(object({
    id              = string
    name            = string
    type            = string
    ttl             = number
    content         = optional(string)
    proxied         = optional(bool)
    priority        = optional(number)
    comment         = optional(string)
    tags            = optional(set(string))
    private_routing = optional(bool)
    settings = optional(object({
      flatten_cname = optional(bool)
      ipv4_only     = optional(bool)
      ipv6_only     = optional(bool)
    }))
    data = optional(object({
      algorithm      = optional(number)
      altitude       = optional(number)
      certificate    = optional(string)
      digest         = optional(string)
      digest_type    = optional(number)
      fingerprint    = optional(string)
      flags          = optional(any)
      key_tag        = optional(number)
      lat_degrees    = optional(number)
      lat_direction  = optional(string)
      lat_minutes    = optional(number)
      lat_seconds    = optional(number)
      long_degrees   = optional(number)
      long_direction = optional(string)
      long_minutes   = optional(number)
      long_seconds   = optional(number)
      matching_type  = optional(number)
      order          = optional(number)
      port           = optional(number)
      precision_horz = optional(number)
      precision_vert = optional(number)
      preference     = optional(number)
      priority       = optional(number)
      protocol       = optional(number)
      public_key     = optional(string)
      regex          = optional(string)
      replacement    = optional(string)
      selector       = optional(number)
      service        = optional(string)
      size           = optional(number)
      tag            = optional(string)
      target         = optional(string)
      type           = optional(number)
      usage          = optional(number)
      value          = optional(string)
      weight         = optional(number)
    }))
  }))
  nullable = false
  validation {
    condition     = alltrue([for record in values(var.dns_records) : can(regex("^[0-9a-fA-F]{32}$", record.id))])
    error_message = "Every DNS record id must be a 32-character hexadecimal identifier."
  }
  validation {
    condition     = alltrue([for record in values(var.dns_records) : try(record.ttl == floor(record.ttl) && (record.ttl == 1 || (record.ttl >= 30 && record.ttl <= 86400)), false)])
    error_message = "DNS ttl must be 1 (automatic) or an integer from 30 to 86400; provider plan limits still apply."
  }
  validation {
    condition     = length(distinct([for record in values(var.dns_records) : record.id])) == length(var.dns_records)
    error_message = "A DNS record id must be managed only once within a zone."
  }
}

variable "rulesets" {
  description = "User-owned rulesets; action-dependent rule payloads are supplied as JSON."
  type = map(object({
    id          = string
    name        = string
    description = optional(string)
    kind        = string
    phase       = string
    rules_json  = string
  }))
  nullable = false
  validation {
    condition     = alltrue([for ruleset in values(var.rulesets) : can(regex("^[0-9a-fA-F]{32}$", ruleset.id)) && ruleset.kind == "zone"])
    error_message = "Rulesets must have valid identifiers and be user-owned zone rulesets."
  }
  validation {
    condition     = alltrue([for ruleset in values(var.rulesets) : can(jsondecode(ruleset.rules_json)) && startswith(trimspace(ruleset.rules_json), "[")])
    error_message = "rules_json must encode a list of rules."
  }
}

variable "settings" {
  description = "Zone settings; only the provider-defined value crosses a JSON boundary."
  type = map(object({
    setting_id = string
    value_json = string
  }))
  nullable = false
  validation {
    condition     = alltrue([for setting in values(var.settings) : try(length(trimspace(setting.setting_id)) > 0 && jsondecode(setting.value_json) != null, false)])
    error_message = "Each setting needs an identifier and a non-null valid JSON value."
  }
  validation {
    condition     = length(distinct([for setting in values(var.settings) : setting.setting_id])) == length(var.settings)
    error_message = "A setting_id must be managed only once within a zone."
  }
}

variable "zone" {
  description = "One existing zone; its local directory alias is unrelated to its Cloudflare ID."
  type = object({
    id                  = string
    name                = string
    type                = string
    paused              = bool
    vanity_name_servers = optional(list(string))
  })
  nullable = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{32}$", var.zone.id))
    error_message = "zone.id must be a 32-character hexadecimal identifier."
  }
  validation {
    condition     = try(length(trimspace(var.zone.name)) > 0 && contains(["full", "partial", "secondary", "internal"], var.zone.type), false)
    error_message = "zone must have a name and a supported type."
  }
}
