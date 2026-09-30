# The primary organization: the one that contains your B.O.R.I.S data account.
# Apply with credentials for the organization's management account.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# The module requires its provider to be configured for the module's region input.
provider "aws" {
  region = "eu-central-1"
}

variable "connection_secret" {
  type        = string
  description = "Per-connection secret issued by the B.O.R.I.S team. Supply it as TF_VAR_connection_secret rather than putting it in a committed .tfvars."
  sensitive   = true
}

module "boris_aws" {
  # Published as:
  #   source  = "sirob-tech/boris-ai/aws"
  #   version = "~> 1.0"
  source = "../../"

  vendor_aws_account_id = "111122223333"
  region                = "eu-central-1" # where B.O.R.I.S stores your data
  external_id           = "00000000-0000-0000-0000-000000000000"

  active_regions = ["eu-central-1", "us-east-1"]

  # The member account that holds your B.O.R.I.S data. Only this account gets
  # the data management role; every other account is read-only.
  data_account_id = "444455556666"

  # Registers from inside apply (the default), authenticated by this secret.
  connection_secret = var.connection_secret
}

output "organization_id" {
  description = "Registered AWS organization ID."
  value       = module.boris_aws.organization_id
}
