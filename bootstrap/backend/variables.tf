variable "account_id" {
  description = "Cloudflare account identifier supplied privately."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal identifier."
  }
}

variable "bucket_name" {
  description = "Private dedicated state bucket property."
  type        = string
  nullable    = false

}

variable "jurisdiction" {
  description = "Private dedicated state bucket property."
  type        = string
  nullable    = false
  validation {
    condition     = contains(["default", "eu", "fedramp", "us"], var.jurisdiction)
    error_message = "Specify a supported R2 jurisdiction."
  }
}

variable "config_bucket" {
  description = "A separate private R2 bucket for revisioned configuration and Worker sources."
  type = object({
    name                  = string
    location              = string
    jurisdiction          = string
    public_access_enabled = bool
  })
  nullable = false

  validation {
    condition     = var.config_bucket.public_access_enabled == false
    error_message = "Public access is forbidden for the configuration bucket."
  }

  validation {
    condition     = contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], var.config_bucket.location)
    error_message = "Specify a supported configuration bucket location."
  }

  validation {
    condition     = contains(["default", "eu", "fedramp", "us"], var.config_bucket.jurisdiction)
    error_message = "Specify a supported configuration bucket jurisdiction."
  }

  validation {
    condition     = var.config_bucket.name != var.bucket_name
    error_message = "Configuration and state must use separate buckets."
  }
}

variable "location" {
  description = "Private dedicated state bucket property."
  type        = string
  nullable    = false
  validation {
    condition     = contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], var.location)
    error_message = "Specify a supported lowercase R2 region."
  }
}

variable "public_access_enabled" {
  description = "The dedicated state bucket must remain private."
  type        = bool
  nullable    = false
  validation {
    condition     = var.public_access_enabled == false
    error_message = "Public access is forbidden for the state bucket."
  }
}
