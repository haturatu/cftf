variable "account_id" {
  description = "Cloudflare account identifier supplied privately."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal identifier."
  }
}

variable "ip_lists" {
  description = "Account-level IP lists used by WAF expressions. The Free plan allows one IP list. Omit items when importing an existing list so its entries are preserved; an explicit empty list clears it."
  type = map(object({
    import_id   = optional(string)
    name        = string
    description = optional(string)
    items = optional(list(object({
      ip      = string
      comment = optional(string)
    })))
  }))
  default  = {}
  nullable = false
  validation {
    condition = length(var.ip_lists) <= 1 && alltrue([
      for list in values(var.ip_lists) :
      can(regex("^[a-z0-9_]{1,50}$", list.name)) &&
      (list.import_id == null || can(regex("^[0-9a-fA-F]{32}$", list.import_id))) &&
      length(coalesce(list.items, [])) <= 10000 &&
      alltrue([
        for item in coalesce(list.items, []) :
        can(cidrhost(item.ip, 0)) || can(cidrhost(
          can(regex(":", item.ip)) ? "${item.ip}/128" : "${item.ip}/32",
          0
        ))
      ])
    ])
    error_message = "The Free plan allows one IP list with a lowercase name of 1-50 characters, at most 10,000 valid IP/CIDR items, and an optional 32-character id."
  }
}

variable "turnstile_widgets" {
  description = "Turnstile widgets for forms and login pages. The Free plan allows up to twenty widgets."
  type = map(object({
    import_id       = optional(string)
    name            = string
    domains         = list(string)
    mode            = string
    clearance_level = optional(string)
    region          = optional(string, "world")
  }))
  default  = {}
  nullable = false
  validation {
    condition = length(var.turnstile_widgets) <= 20 && alltrue([
      for widget in values(var.turnstile_widgets) :
      length(widget.domains) > 0 &&
      contains(["non-interactive", "invisible", "managed"], widget.mode) &&
      (widget.clearance_level == null || contains(["no_clearance", "jschallenge", "managed", "interactive"], widget.clearance_level)) &&
      contains(["world", "china"], widget.region) &&
      (widget.import_id == null || length(trimspace(widget.import_id)) > 0)
    ])
    error_message = "Turnstile widgets need at least one domain, a supported mode, an optional valid clearance level, and the Free plan limit of twenty."
  }
}
