output "organization_id" {
  description = "AWS organization ID this module registers with B.O.R.I.S."
  value       = local.organization_id
}

output "management_account_id" {
  description = "The organization's management account, where the stack and the management-account read-only role live."
  value       = local.management_account_id
}

output "stack_id" {
  description = "ID of the CloudFormation stack."
  value       = aws_cloudformation_stack.boris_ai.id
}

output "management_account_role_arn" {
  description = "Read-only role B.O.R.I.S assumes in the management account."
  value       = local.management_account_role_arn
}

output "data_management_role_arn" {
  description = "Data management role in data_account_id, or null for a secondary organization."
  value       = lookup(local.registration_fields, "data_management_role_arn", null)
}

output "target_organizational_unit_ids" {
  description = "Organizational units the read-only StackSet targets (the root when none were given)."
  value       = local.target_ou_ids
}

# The secret is referenced as $BORIS_CONNECTION_SECRET, never embedded: outputs
# are stored in state in cleartext whether or not they are marked sensitive.
output "registration_curl" {
  description = "Manual registration command to run after apply (when enable_self_registration is false). Export BORIS_CONNECTION_SECRET in your shell first; read it with `terraform output -raw`."
  value = format(
    "curl -X PUT '%s/aws/install/%s' -H 'Content-Type: application/json' -H \"Authorization: Bearer $BORIS_CONNECTION_SECRET\" -d '%s'",
    local.registration_endpoint != "" ? local.registration_endpoint : "https://install.getboris.ai",
    local.organization_id,
    local.registration_body,
  )
}
