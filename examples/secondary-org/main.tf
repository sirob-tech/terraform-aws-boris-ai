# A secondary organization: read-only everywhere, no data account. Register your
# primary organization first; B.O.R.I.S refuses a secondary until it has one.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# The same region as the primary organization, whose data account holds your data.
provider "aws" {
  region = "eu-central-1"
}

module "boris_aws" {
  # Published as:
  #   source  = "sirob-tech/boris-ai/aws"
  #   version = "~> 1.0"
  source = "../../"

  vendor_aws_account_id = "111122223333"
  region                = "eu-central-1" # where B.O.R.I.S stores your data
  external_id           = "00000000-0000-0000-0000-000000000000"

  active_regions = ["us-east-1"]

  # Deploy only to these OUs rather than the whole organization.
  target_organizational_unit_ids = ["ou-ab12-11111111", "ou-ab12-22222222"]

  # Register by hand with the output below instead of from inside apply.
  enable_self_registration = false
}

# Run with BORIS_CONNECTION_SECRET exported: terraform output -raw register | sh
output "register" {
  description = "Manual registration command."
  value       = module.boris_aws.registration_curl
}
