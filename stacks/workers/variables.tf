variable "account_id" {
  description = "Cloudflare account identifier supplied privately."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal identifier."
  }
}

variable "worker_crons" {
  description = "Cron schedules referencing local Worker aliases."
  type = map(object({
    worker_key = string
    schedules  = list(object({ cron = string }))
  }))
  nullable = false
  validation {
    condition     = alltrue([for cron in values(var.worker_crons) : try(contains(keys(var.workers), cron.worker_key), false)])
    error_message = "Each Cron must reference an existing local Worker key."
  }
  validation {
    condition     = alltrue([for cron in values(var.worker_crons) : length(cron.schedules) > 0])
    error_message = "Each Cron entry must contain at least one schedule."
  }
}

variable "worker_domains" {
  description = "Custom domains using private Zone IDs and local Worker references."
  type = map(object({
    id          = string
    hostname    = string
    worker_key  = string
    environment = optional(string)
    zone_id     = string
  }))
  nullable = false
  validation {
    condition     = alltrue([for domain in values(var.worker_domains) : can(regex("^[0-9a-fA-F]{32}$", domain.id)) && can(regex("^[0-9a-fA-F]{32}$", domain.zone_id))])
    error_message = "Custom domain and Zone IDs must be 32-character hexadecimal identifiers."
  }
  validation {
    condition     = alltrue([for domain in values(var.worker_domains) : try(contains(keys(var.workers), domain.worker_key), false)])
    error_message = "Each custom domain must reference an existing local Worker key."
  }
}

variable "worker_routes" {
  description = "Zone routes using private Zone IDs and local Worker references."
  type = map(object({
    id         = string
    zone_id    = string
    pattern    = string
    worker_key = optional(string)
  }))
  nullable = false
  validation {
    condition     = alltrue([for route in values(var.worker_routes) : can(regex("^[0-9a-fA-F]{32}$", route.id)) && can(regex("^[0-9a-fA-F]{32}$", route.zone_id))])
    error_message = "Route and Zone IDs must be 32-character hexadecimal identifiers."
  }
  validation {
    condition     = alltrue([for route in values(var.worker_routes) : route.worker_key == null ? true : contains(keys(var.workers), route.worker_key)])
    error_message = "Each route Worker key must exist unless the route intentionally has no Worker."
  }
}

variable "workers" {
  description = "Private Worker definitions; source paths are absolute and Secret values stay in Cloudflare."
  type = map(object({
    bindings = list(object({
      name = string
      type = string
      text = string
    }))
    body_part           = optional(string)
    compatibility_date  = string
    compatibility_flags = set(string)
    logpush             = bool
    main_module         = optional(string)
    name                = string
    observability = optional(object({
      enabled            = bool
      head_sampling_rate = optional(number)
      issues = optional(object({
        enabled = optional(bool)
      }))
      logs = optional(object({
        destinations       = optional(list(string))
        enabled            = bool
        head_sampling_rate = optional(number)
        invocation_logs    = bool
        persist            = optional(bool)
      }))
      traces = optional(object({
        destinations       = optional(list(string))
        enabled            = optional(bool)
        head_sampling_rate = optional(number)
        persist            = optional(bool)
        propagation_policy = optional(string)
      }))
    }))
    preserve_binding_types = set(string)
    secret_names           = optional(set(string), [])
    source_path            = string
    subdomain              = object({ enabled = bool, previews_enabled = bool })
    usage_model            = string
  }))
  nullable = false
  validation {
    condition     = alltrue([for worker in values(var.workers) : try(fileexists(worker.source_path), false)])
    error_message = "Each Worker source_path must identify an existing source file."
  }
  validation {
    condition     = alltrue([for worker in values(var.workers) : (worker.main_module != null) != (worker.body_part != null)])
    error_message = "Specify exactly one of main_module or body_part per Worker."
  }
  validation {
    condition     = alltrue([for worker in values(var.workers) : try(contains(["standard", "bundled", "unbound"], worker.usage_model), false)])
    error_message = "Worker usage_model must be supported by the provider."
  }
  validation {
    condition     = alltrue([for worker in values(var.workers) : try(length(worker.secret_names) == 0 || contains(worker.preserve_binding_types, "secret_text"), false)])
    error_message = "Existing Secret names require preserving the secret_text binding type."
  }
  validation {
    condition     = alltrue(flatten([for worker in values(var.workers) : [for binding in worker.bindings : binding.type == "plain_text"]]))
    error_message = "Only current plain_text bindings are supported; keep Secret values outside Terraform."
  }
}
