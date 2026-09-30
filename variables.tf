# Every value that reaches the registration local-exec is validated to a charset
# with no single quote or shell metacharacter; registration.tf lists them.

# ---------------------------------------------------------------------------
# Identity / contract inputs
# ---------------------------------------------------------------------------

variable "vendor_aws_account_id" {
  type        = string
  description = "The B.O.R.I.S AWS account ID every role trusts, from your B.O.R.I.S install details; not secret."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.vendor_aws_account_id))
    error_message = "vendor_aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  type        = string
  description = "Where B.O.R.I.S stores your data: \"eu-central-1\" or \"us-east-1\", as given in your B.O.R.I.S install details. The module requires its aws provider to be configured for this region, and creates the stack and its StackSet instances there."
  nullable    = false

  validation {
    condition     = contains(["eu-central-1", "us-east-1"], var.region)
    error_message = "region must be \"eu-central-1\" or \"us-east-1\", the regions B.O.R.I.S can store your data in."
  }
}

variable "external_id" {
  type        = string
  description = "Your B.O.R.I.S customer ID. Every role requires it as the sts:ExternalId, and B.O.R.I.S presents it on every assume."

  # B.O.R.I.S sends the customer UUID as the external ID, so any other shape
  # would build roles it can never assume.
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.external_id))
    error_message = "external_id must be your B.O.R.I.S customer ID, a full UUID such as \"123e4567-e89b-12d3-a456-426614174000\"."
  }
}

# ---------------------------------------------------------------------------
# Read-only targeting
# ---------------------------------------------------------------------------

variable "target_organizational_unit_ids" {
  type        = list(string)
  description = "Organizational units (ou-...) the read-only role is deployed to, including accounts added to them later. Empty (default) targets the organization root, which is every member account."
  default     = []

  validation {
    condition     = alltrue([for id in var.target_organizational_unit_ids : can(regex("^(ou-[0-9a-z]{4,32}-[0-9a-z]{8,32}|r-[0-9a-z]{4,32})$", id))])
    error_message = "target_organizational_unit_ids entries must be organizational unit IDs (\"ou-ab12-cd345678\") or the root ID (\"r-ab12\")."
  }
}

# ---------------------------------------------------------------------------
# Data destination (primary organization only)
# ---------------------------------------------------------------------------

variable "data_account_id" {
  type        = string
  description = "The member account where B.O.R.I.S stores your data, in region. Set it on your primary organization only; it receives the data management role and becomes your data destination at registration. Leave unset for every other organization."
  default     = null

  validation {
    condition     = var.data_account_id == null || can(regex("^[0-9]{12}$", var.data_account_id))
    error_message = "data_account_id must be a 12-digit AWS account ID, or unset."
  }
}

# ---------------------------------------------------------------------------
# Registration values
# ---------------------------------------------------------------------------

variable "active_regions" {
  type        = list(string)
  description = "The AWS regions where you actively deploy workloads, e.g. [\"eu-central-1\", \"us-east-1\"]. Scopes what the B.O.R.I.S memory scrape retains; it does not restrict what B.O.R.I.S reads. Required, with at least one entry."

  validation {
    condition     = length(var.active_regions) > 0
    error_message = "active_regions must list at least one region."
  }

  # The only shell-quoting control for this field: jsonencode leaves a single
  # quote unescaped inside the single-quoted body in registration.tf.
  validation {
    condition     = alltrue([for r in var.active_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]{1,2}$", r))])
    error_message = "active_regions entries must each be a bare lowercase AWS region, e.g. \"us-east-1\" or \"ap-southeast-2\". An availability zone is not a region."
  }
}

# ---------------------------------------------------------------------------
# Optional self-registration (single-apply onboarding)
# ---------------------------------------------------------------------------

variable "enable_self_registration" {
  type        = bool
  description = "When true (default), the module calls the B.O.R.I.S registration endpoint after the stack is in place (idempotent PUT via local-exec), which needs connection_secret. Set false to register yourself with the registration_curl output."
  default     = true
  nullable    = false
}

variable "registration_endpoint" {
  type        = string
  description = "Base URL of the B.O.R.I.S registration endpoint. Keep the default unless the B.O.R.I.S team gives you another."
  default     = "https://install.getboris.ai"
  nullable    = false

  validation {
    condition     = can(regex("^https://[A-Za-z0-9.:/_-]+$", var.registration_endpoint))
    error_message = "registration_endpoint must be an https:// URL containing only letters, digits, and . : / _ -"
  }
}

variable "connection_secret" {
  type        = string
  description = "Per-connection onboarding secret issued by the B.O.R.I.S team, sent as an Authorization: Bearer credential. Required unless enable_self_registration is false. It binds to this organization on first use and stays valid, so keep it for re-applies."
  default     = ""
  nullable    = false
  sensitive   = true

  validation {
    condition     = !var.enable_self_registration || length(var.connection_secret) > 0
    error_message = "connection_secret is required because enable_self_registration is on (the default). Ask the B.O.R.I.S team to issue one for this organization, or set enable_self_registration = false and run the registration_curl output yourself."
  }

  # Exact shape, so a truncated paste fails at plan instead of as a 401 mid-apply.
  validation {
    condition     = var.connection_secret == "" || can(regex("^boris_[a-z2-7]{16}_[a-z2-7]{52}$", var.connection_secret))
    error_message = "connection_secret must look like boris_<16 chars>_<52 chars>, using only lowercase letters and the digits 2-7. Check for a truncated copy-paste."
  }
}
