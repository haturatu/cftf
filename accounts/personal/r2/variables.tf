variable "account_id" {
  description = "Cloudflare account identifier supplied privately."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal identifier."
  }
}

variable "buckets" {
  description = "Private bucket definitions; public access requires a separate explicit opt-in."
  type = map(object({
    name                  = string
    location              = string
    jurisdiction          = string
    storage_class         = optional(string)
    public_access_enabled = bool
    allow_public_access   = optional(bool, false)
    lifecycle_rules = list(object({
      abort_multipart_uploads_transition = optional(object({
        condition = optional(object({
          max_age = number
          type    = string
        }))
      }))
      conditions = object({
        prefix = string
      })
      delete_objects_transition = optional(object({
        condition = optional(object({
          date    = optional(string)
          max_age = optional(number)
          type    = string
        }))
      }))
      enabled = bool
      id      = string
      storage_class_transitions = optional(list(object({
        condition = object({
          date    = optional(string)
          max_age = optional(number)
          type    = string
        })
        storage_class = string
      })))
    }))
    cors_rules = optional(list(object({
      allowed = object({
        headers = optional(list(string))
        methods = list(string)
        origins = list(string)
      })
      expose_headers  = optional(list(string))
      id              = optional(string)
      max_age_seconds = optional(number)
    })))
  }))
  nullable = false
  validation {
    condition     = alltrue([for bucket in values(var.buckets) : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", bucket.name))])
    error_message = "Bucket names must contain 3 to 63 lowercase letters, numbers, or hyphens and begin and end with a letter or number."
  }
  validation {
    condition     = alltrue([for bucket in values(var.buckets) : try(contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], bucket.location), false)])
    error_message = "Each bucket location must be a supported lowercase R2 region."
  }
  validation {
    condition     = alltrue([for bucket in values(var.buckets) : try(contains(["default", "eu", "fedramp", "us"], bucket.jurisdiction), false)])
    error_message = "Each bucket must specify a supported R2 jurisdiction."
  }
  validation {
    condition     = alltrue([for bucket in values(var.buckets) : bucket.storage_class == null ? true : contains(["Standard", "InfrequentAccess"], bucket.storage_class)])
    error_message = "storage_class must be Standard or InfrequentAccess when specified."
  }
  validation {
    condition     = alltrue([for bucket in values(var.buckets) : try(!bucket.public_access_enabled || bucket.allow_public_access, false)])
    error_message = "Public R2 access requires allow_public_access = true for the same bucket."
  }
  validation {
    condition     = length(distinct([for bucket in values(var.buckets) : bucket.name])) == length(var.buckets)
    error_message = "Each bucket name must be managed only once."
  }
}
