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
  description = "User-owned zone rulesets; omit id to create a new ruleset, or supply the existing id to import one."
  type = map(object({
    id          = optional(string)
    name        = string
    description = optional(string)
    kind        = string
    phase       = string
    rules_json  = string
  }))
  nullable = false
  validation {
    condition = alltrue([
      for ruleset in values(var.rulesets) :
      ruleset.kind == "zone" &&
      !contains(["ddos_l7", "http_request_firewall_managed", "http_response_firewall_managed"], ruleset.phase) &&
      (ruleset.id == null || can(regex("^[0-9a-fA-F]{32}$", ruleset.id)))
    ])
    error_message = "Rulesets must be user-owned zone rulesets; managed phases belong to managed_entrypoints. An existing id must be a 32-character hexadecimal identifier."
  }
  validation {
    condition     = alltrue([for ruleset in values(var.rulesets) : can(jsondecode(ruleset.rules_json)) && startswith(trimspace(ruleset.rules_json), "[")])
    error_message = "rules_json must encode a list of rules."
  }
  validation {
    condition     = length(distinct([for ruleset in values(var.rulesets) : ruleset.phase])) == length(var.rulesets)
    error_message = "Each ruleset phase can have only one entrypoint ruleset per zone."
  }
  validation {
    condition = alltrue([
      for ruleset in values(var.rulesets) :
      ruleset.phase != "http_request_firewall_custom" || length(try(jsondecode(ruleset.rules_json), [])) <= 5
    ])
    error_message = "The Free plan allows at most five custom WAF rules per zone."
  }
  validation {
    condition = alltrue([
      for ruleset in values(var.rulesets) :
      ruleset.phase != "http_ratelimit" || (
        length(try(jsondecode(ruleset.rules_json), [])) <= 1 &&
        alltrue([
          for rule in try(jsondecode(ruleset.rules_json), []) :
          contains(["block", "challenge", "js_challenge", "managed_challenge", "log"], try(rule.action, "")) &&
          try(rule.ratelimit.period, 0) == 10 &&
          contains(try(rule.ratelimit.characteristics, []), "cf.colo.id") &&
          try(rule.ratelimit.requests_per_period, 0) > 0 &&
          try(rule.ratelimit.score_per_period, null) == null &&
          (
            (contains(["challenge", "js_challenge", "managed_challenge"], try(rule.action, "")) && try(rule.ratelimit.mitigation_timeout, null) == 0) ||
            (!contains(["challenge", "js_challenge", "managed_challenge"], try(rule.action, "")) && try(rule.ratelimit.mitigation_timeout, 10) == 10)
          )
        ])
      )
    ])
    error_message = "The Free plan allows one rate limiting rule per zone with period 10, cf.colo.id in characteristics, and requests_per_period. Challenge actions require mitigation_timeout 0; other actions require 10."
  }
}

variable "managed_entrypoints" {
  description = "Zone entrypoint rulesets that deploy or override Cloudflare-managed rulesets. id is the zone entrypoint ruleset id, not the managed ruleset id. Omit id to create a new entrypoint."
  type = map(object({
    id          = optional(string)
    name        = string
    description = optional(string)
    phase       = string
    rules_json  = string
  }))
  default  = {}
  nullable = false
  validation {
    condition = alltrue([
      for ruleset in values(var.managed_entrypoints) :
      contains(["http_request_firewall_managed", "ddos_l7"], ruleset.phase) &&
      (ruleset.id == null || can(regex("^[0-9a-fA-F]{32}$", ruleset.id)))
    ])
    error_message = "Managed entrypoints require a supported managed phase and an optional 32-character entrypoint ruleset id."
  }
  validation {
    condition     = alltrue([for ruleset in values(var.managed_entrypoints) : can(jsondecode(ruleset.rules_json)) && startswith(trimspace(ruleset.rules_json), "[")])
    error_message = "managed_entrypoints.rules_json must encode a list of rules."
  }
  validation {
    condition     = alltrue([for ruleset in values(var.managed_entrypoints) : length(try(jsondecode(ruleset.rules_json), [])) > 0])
    error_message = "managed_entrypoints.rules_json must contain at least one execute rule; an empty list would remove the managed ruleset deployment."
  }
  validation {
    condition = alltrue([
      for ruleset in values(var.managed_entrypoints) :
      length([
        for rule in try(jsondecode(ruleset.rules_json), []) :
        rule
        if try(rule.action, "") == "execute" &&
        try(rule.enabled, true) != false &&
        length(trimspace(try(rule.expression, ""))) > 0 &&
        can(regex("^[0-9a-fA-F]{32}$", try(rule.action_parameters.id, "")))
      ]) > 0
    ])
    error_message = "managed_entrypoints must contain at least one enabled execute rule with an expression and a 32-character action_parameters.id."
  }
  validation {
    condition = alltrue([
      for ruleset in values(var.managed_entrypoints) :
      length([
        for rule in try(jsondecode(ruleset.rules_json), []) :
        rule
        if try(rule.action, "") == "skip" && trimspace(try(rule.expression, "")) == "true"
      ]) == 0
    ])
    error_message = "An unconditional skip rule would disable the managed ruleset deployment; scope the skip expression to the intended exceptions."
  }
  validation {
    condition     = length(distinct([for ruleset in values(var.managed_entrypoints) : ruleset.phase])) == length(var.managed_entrypoints)
    error_message = "Each managed ruleset phase can have only one entrypoint ruleset per zone."
  }
  validation {
    condition = length(setintersection(
      toset([for ruleset in values(var.rulesets) : ruleset.phase]),
      toset([for ruleset in values(var.managed_entrypoints) : ruleset.phase]),
    )) == 0
    error_message = "A phase cannot be owned by both rulesets and managed_entrypoints."
  }
}

variable "existing_zone_ruleset_phases" {
  description = "Phases that already have a zone entrypoint ruleset in Cloudflare. Used to prevent creating a duplicate outside Terraform; set by the stack from the rulesets data source."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "bot_management" {
  description = "Free plan bot controls: Bot Fight Mode, AI bot blocking, AI Labyrinth, and managed robots.txt."
  type = object({
    fight_mode                  = optional(bool)
    ai_bots_protection          = optional(string)
    ai_training                 = optional(string)
    ai_user                     = optional(string)
    aisearch                    = optional(string)
    crawler_protection          = optional(string)
    cf_robots_variant           = optional(string)
    is_robots_txt_managed       = optional(bool)
    bot_preference_sync_enabled = optional(bool)
  })
  default = null
  validation {
    condition = var.bot_management == null || (
      (var.bot_management.ai_bots_protection == null || contains(["block", "disabled", "only_on_ad_pages"], var.bot_management.ai_bots_protection)) &&
      (var.bot_management.ai_training == null || contains(["disabled", "disallow", "block", "only_on_ad_pages"], var.bot_management.ai_training)) &&
      (var.bot_management.ai_user == null || contains(["disabled", "block", "only_on_ad_pages"], var.bot_management.ai_user)) &&
      (var.bot_management.aisearch == null || contains(["disabled", "block", "only_on_ad_pages"], var.bot_management.aisearch)) &&
      (var.bot_management.crawler_protection == null || contains(["enabled", "disabled"], var.bot_management.crawler_protection)) &&
      (var.bot_management.cf_robots_variant == null || contains(["off", "policy_only"], var.bot_management.cf_robots_variant))
    )
    error_message = "bot_management contains an unsupported value for the selected Free plan bot control."
  }
  validation {
    condition = var.bot_management == null || anytrue([
      for value in values(var.bot_management) : value != null
    ])
    error_message = "bot_management must configure at least one bot control."
  }
}

variable "url_normalization" {
  description = "URL normalization applied before WAF and other request-phase products."
  type = object({
    scope = optional(string, "incoming")
    type  = optional(string, "rfc3986")
  })
  default = null
  validation {
    condition = var.url_normalization == null || (
      contains(["incoming", "both", "none"], var.url_normalization.scope) &&
      contains(["cloudflare", "rfc3986"], var.url_normalization.type)
    )
    error_message = "url_normalization.scope must be incoming, both, or none; type must be cloudflare or rfc3986."
  }
}

variable "dnssec" {
  description = "DNSSEC activation for the zone. DS records must still be published at the registrar."
  type = object({
    status              = optional(string, "active")
    dnssec_use_nsec3    = optional(bool)
    dnssec_multi_signer = optional(bool)
    dnssec_presigned    = optional(bool)
  })
  default = null
  validation {
    condition     = var.dnssec == null || contains(["active", "disabled"], var.dnssec.status)
    error_message = "dnssec.status must be active or disabled."
  }
}

variable "managed_transforms" {
  description = "Cloudflare-managed request and response header transforms, including security headers and leaked credential checks."
  type = object({
    request_headers = optional(set(object({
      id      = string
      enabled = bool
    })), [])
    response_headers = optional(set(object({
      id      = string
      enabled = bool
    })), [])
  })
  default = null
  validation {
    condition = var.managed_transforms == null ? true : (
      (length(var.managed_transforms.request_headers) + length(var.managed_transforms.response_headers) > 0) &&
      alltrue([
        for header in concat(tolist(var.managed_transforms.request_headers), tolist(var.managed_transforms.response_headers)) :
        can(regex("^[a-z0-9_-]+$", header.id))
      ])
    )
    error_message = "managed_transforms must configure at least one transform with a valid identifier."
  }
}

variable "leaked_credential_check" {
  description = "Enable or disable the zone-level leaked credential check. Pair it with the managed transform add_waf_credential_check_status_header."
  type        = bool
  default     = null
}

variable "authenticated_origin_pulls" {
  description = "Enable or disable zone-level Authenticated Origin Pulls. A certificate must already exist at the origin."
  type        = bool
  default     = null
}

variable "access_rules" {
  description = "Zone IP Access Rules. Supply id only when importing an existing rule."
  type = map(object({
    id     = optional(string)
    mode   = string
    notes  = optional(string)
    target = optional(string, "ip")
    value  = string
  }))
  default  = {}
  nullable = false
  validation {
    condition = alltrue([
      for rule in values(var.access_rules) :
      contains(["block", "challenge", "whitelist", "js_challenge", "managed_challenge"], rule.mode) &&
      contains(["ip", "ip6", "ip_range", "asn", "country"], rule.target) &&
      length(trimspace(rule.value)) > 0 &&
      (rule.id == null || can(regex("^[0-9a-fA-F]{32}$", rule.id)))
    ])
    error_message = "Each access rule needs a supported mode, target, value, and an optional 32-character id when importing."
  }
}

variable "user_agent_blocking_rules" {
  description = "Zone User Agent Blocking rules. The Free plan allows ten rules per zone."
  type = map(object({
    id          = optional(string)
    mode        = string
    value       = string
    description = optional(string)
    paused      = optional(bool, false)
  }))
  default  = {}
  nullable = false
  validation {
    condition = length(var.user_agent_blocking_rules) <= 10 && alltrue([
      for rule in values(var.user_agent_blocking_rules) :
      contains(["block", "challenge", "whitelist", "js_challenge", "managed_challenge"], rule.mode) &&
      length(trimspace(rule.value)) > 0 &&
      (rule.id == null || can(regex("^[0-9a-fA-F]{32}$", rule.id)))
    ])
    error_message = "The Free plan allows at most ten user agent blocking rules with supported modes and optional 32-character ids."
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
