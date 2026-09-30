locals {
  template_body = file("${path.module}/templates/boris-ai.yaml")

  # Not inputs: the B.O.R.I.S backend reads the stack and assumes the read-only
  # role by these exact names.
  stack_name         = "BorisAI"
  readonly_role_name = "boris-ai-readonly"

  # Fixed by contract: registration refuses any other data role ARN.
  data_management_role_name = "boris-ai-resources-management-role"

  organization_id       = data.aws_organizations_organization.this.id
  management_account_id = data.aws_organizations_organization.this.master_account_id
  root_id               = data.aws_organizations_organization.this.roots[0].id
  member_account_ids    = [for a in data.aws_organizations_organization.this.non_master_accounts : a.id]

  # Sorted so reordering the list is not a stack change.
  target_ou_ids = length(var.target_organizational_unit_ids) > 0 ? sort(distinct(var.target_organizational_unit_ids)) : [local.root_id]

  has_data_account = var.data_account_id != null

  # Sorted and deduplicated so the registration trigger is stable; neither
  # function can add a character the variable validation did not allow.
  active_regions = sort(distinct(var.active_regions))

  # Commercial partition only: the endpoint accepts arn:aws: ARNs and nothing else.
  management_account_role_arn = "arn:aws:iam::${local.management_account_id}:role/${local.readonly_role_name}"

  # Null entries drop out, so a secondary organization sends no data fields at all.
  registration_fields = {
    for k, v in {
      management_account_id       = local.management_account_id
      readonly_role_name          = local.readonly_role_name
      active_regions              = join(",", local.active_regions)
      vendor_region               = var.region
      org_deployment_region       = var.region
      management_account_role_arn = local.management_account_role_arn
      data_account_id             = var.data_account_id
      data_management_role_arn    = local.has_data_account ? "arn:aws:iam::${var.data_account_id}:role/${local.data_management_role_name}" : null
    } : k => v if v != null
  }

  registration_body = jsonencode(local.registration_fields)

  # A trailing slash would render a double-slash URL, which gateways often 404.
  registration_endpoint = trimsuffix(var.registration_endpoint, "/")
}
