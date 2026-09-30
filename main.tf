data "aws_caller_identity" "current" {}

data "aws_organizations_organization" "this" {}

data "aws_region" "current" {}

# One stack, as the CloudFormation-only install had: the management-account role
# plus the read-only and data StackSets. Terraform only passes parameters.
resource "aws_cloudformation_stack" "boris_ai" {
  name          = var.stack_name
  template_body = local.template_body
  capabilities  = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"]

  # Every parameter is passed explicitly, including the empty data account, so
  # a template default never shows up as drift.
  parameters = {
    VendorAccountId       = var.vendor_aws_account_id
    DataStorageAccountId  = local.has_data_account ? var.data_account_id : ""
    ExternalId            = var.external_id
    ReadOnlyRoleName      = var.readonly_role_name
    Region                = var.region
    OrganizationalUnitIds = join(",", local.target_ou_ids)
    OrganizationRootId    = local.root_id
  }

  tags = {
    boris-ai-project = "BorisAI"
  }

  # StackSet operations across a large organization outlast the 30m default.
  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }

  lifecycle {
    # B.O.R.I.S looks for this stack and its StackSets in the registered
    # org_deployment_region, which is var.region.
    precondition {
      condition     = data.aws_region.current.region == var.region
      error_message = "This module requires its aws provider to be configured for region (${var.region}); it is set to ${data.aws_region.current.region}."
    }

    # CallAs SELF with service-managed permissions only works from the management account.
    precondition {
      condition     = data.aws_caller_identity.current.account_id == local.management_account_id
      error_message = "Apply this module with credentials for the organization's management account (${local.management_account_id}); these credentials are for ${data.aws_caller_identity.current.account_id}."
    }

    # StackSets never deploy into the management account, so the data role could not exist there.
    precondition {
      condition     = !local.has_data_account || var.data_account_id != local.management_account_id
      error_message = "data_account_id must be a member account, not the management account."
    }

    precondition {
      condition     = !local.has_data_account || contains(local.member_account_ids, coalesce(var.data_account_id, "-"))
      error_message = "data_account_id ${coalesce(var.data_account_id, "-")} is not a member account of organization ${local.organization_id}."
    }
  }
}
