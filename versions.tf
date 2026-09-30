# 1.9 for cross-variable validation. AWS provider 6 for aws_region's region
# attribute; otherwise the module uses only long-stable resources.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
