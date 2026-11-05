variable "name" {
  description = "Name prefix for every resource. The NLB and target group take it as their name, so it must be at most 32 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-32 characters of letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "vpc_id" {
  description = "VPC of the database."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the NLB, one per Availability Zone. The endpoint service is offered in exactly these AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must not be empty."
  }
}

variable "port" {
  description = "Port the database listens on, and the port the NLB exposes."
  type        = number
  default     = 5432
}

variable "database_security_group_id" {
  description = "Security group of the database. When set, the NLB may reach only this group on the port, and the module adds an inbound rule to it admitting the NLB."
  type        = string
  default     = null
}

variable "target_cidr_blocks" {
  description = "CIDR blocks the NLB may reach on the port when database_security_group_id is not set. Defaults to the VPC's primary CIDR block."
  type        = list(string)
  default     = []
}

variable "allowed_principals" {
  description = "IAM role ARNs allowed to create endpoints to the service: the endpoint-manager role Unblocked gives you."
  type        = list(string)

  validation {
    condition     = length(var.allowed_principals) > 0 && alltrue([for p in var.allowed_principals : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", p))])
    error_message = "allowed_principals must be a non-empty list of IAM role ARNs."
  }
}

variable "verification_external_id" {
  description = "External ID Unblocked shows on its PrivateLink setup page. The verification role requires it, so only your Unblocked organization can assume the role."
  type        = string

  validation {
    condition     = can(regex("^unblocked_privatelink_[0-9a-f]{32}$", var.verification_external_id))
    error_message = "verification_external_id must be the value Unblocked shows: unblocked_privatelink_ followed by 32 hexadecimal characters."
  }
}

variable "verification_role_name" {
  description = "Name of the role Unblocked assumes to verify that you own the endpoint service. The module prefixes it with UnblockedPrivateLink- unless it already starts with UnblockedPrivateLink, and the full name must be at most 64 characters."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]+$", var.verification_role_name)) && length(startswith(var.verification_role_name, "UnblockedPrivateLink") ? var.verification_role_name : "UnblockedPrivateLink-${var.verification_role_name}") <= 64
    error_message = "verification_role_name must be letters, digits and +=,.@_-, and at most 64 characters once prefixed with UnblockedPrivateLink-."
  }
}

variable "unblocked_region" {
  description = "Region Unblocked connects from. When it differs from this provider's region, the service is offered to it cross-region."
  type        = string
  default     = "us-west-2"
}

variable "auto_accept_connections" {
  description = "Accept endpoint connections from allowed principals automatically. When false, you accept each connection before traffic flows."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
