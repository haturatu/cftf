variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{32}$", var.account_id))
    error_message = "Supply a valid account identifier privately."
  }
}
variable "zone_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{32}$", var.zone_id))
    error_message = "Supply a valid zone identifier privately."
  }
}
variable "database_name" {
  type    = string
  default = "f2b-api"
}
variable "workers" {
  type = map(object({
    name        = string
    hostname    = string
    source_path = string
  }))
  validation {
    condition     = toset(keys(var.workers)) == toset(["api", "ingest"])
    error_message = "Define exactly the public API and protected ingestion Workers."
  }
  validation {
    condition     = alltrue([for worker in values(var.workers) : fileexists(worker.source_path)])
    error_message = "Worker bundles must exist."
  }
}
variable "sources" {
  type = map(object({ jails = set(string) }))
  validation {
    condition     = length(var.sources) > 0 && alltrue([for name, source in var.sources : can(regex("^[a-z0-9][a-z0-9_-]{0,63}$", name)) && length(source.jails) > 0])
    error_message = "Provide named collection sources with explicit jail scopes."
  }
}
variable "access_organization" {
  type    = object({ name = string, auth_domain = optional(string) })
  default = null
}
