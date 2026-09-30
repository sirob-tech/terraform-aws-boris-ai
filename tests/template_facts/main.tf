# Test helper: reads facts out of the CloudFormation template as text. Regexes,
# not a YAML parse, because the member and data templates are string literals
# inside it and CloudFormation short-form tags defeat yamldecode.

variable "template_path" {
  type = string
}

locals {
  body = file(var.template_path)

  # Each DenyDataPlaneReads statement's actions, sorted, in template order.
  deny_blocks = [
    for m in regexall("(?s)Sid: DenyDataPlaneReads\\s*\\n\\s*Effect: Deny\\s*\\n\\s*Action:\\s*\\n(.*?)\\n\\s*Resource:", local.body) :
    sort([for a in regexall("(?m)^\\s*- (\\S+)\\s*$", m[0]) : a[0]])
  ]

  # The data StackSet is the last resource, so everything between its key and the
  # top-level Outputs is the data account's template.
  data_section  = one(regexall("(?s)\\n  BorisAiDataStackSet:\\n(.*?)\\nOutputs:\\n", local.body))[0]
  outer_outputs = one(regexall("(?s)\\nOutputs:\\n(.*)$", local.body))[0]
  outside_data  = replace(replace(local.body, local.data_section, ""), local.outer_outputs, "")
}

output "size_bytes" {
  value = length(local.body)
}

output "deny_blocks" {
  value = local.deny_blocks
}

output "iam_role_count" {
  value = length(regexall("Type: AWS::IAM::Role\\b", local.body))
}

# Write actions the template must no longer grant anywhere.
output "forbidden_actions" {
  value = distinct(flatten([
    regexall("\\b(?:sqs|events):[A-Za-z*]+", local.body),
    regexall("\\bce:Create[A-Za-z]*", local.body),
  ]))
}

# Mentions of the data role outside the data StackSet and the top-level outputs.
output "data_role_mentions_outside_data_stackset" {
  value = length(regexall("resources-management|ResourcesManagement", local.outside_data))
}

output "data_role_mentions_in_data_stackset" {
  value = length(regexall("boris-ai-resources-management-role", local.data_section))
}

output "data_stackset_is_conditional" {
  value = can(regex("^    Type: AWS::CloudFormation::StackSet\\n    Condition: HasDataStorageAccount\\n", local.data_section))
}

output "data_stackset_auto_deployment_off" {
  value = can(regex("(?s)AutoDeployment:\\s*\\n\\s*Enabled: false", local.data_section))
}

output "data_stackset_pinned_to_account" {
  value = can(regex("(?s)Accounts:\\s*\\n\\s*- !Ref DataStorageAccountId\\s*\\n\\s*AccountFilterType: INTERSECTION", local.data_section))
}

output "version_placeholder_left" {
  value = strcontains(local.body, "{{RELEASE_VERSION}}")
}

# AllowedValues of the top-level Region parameter, in template order.
output "region_allowed" {
  value = [for m in regexall("(?m)^      - (\\S+)$", one(regexall("(?s)\\n  Region:\\n.*?AllowedValues:\\n((?:      - \\S+\\n)+)", local.body))[0]) : m[0]]
}

# The two region parameters Region replaced; any mention means one came back.
output "split_region_mentions" {
  value = length(regexall("VendorRegion|DataRegion", local.body))
}

# The Regions each StackSet deploys its instances to.
output "readonly_stackset_regions" {
  value = one(regexall("(?s)\\n  BorisAiStackSet:\\n.*?Regions:\\n\\s*- (!Ref \\S+)\\n", local.body))[0]
}

output "data_stackset_regions" {
  value = one(regexall("(?s)Regions:\\n\\s*- (!Ref \\S+)\\n", local.data_section))[0]
}

# Anything that would let a reader take a region from the stack's outputs.
output "region_outputs" {
  value = length(regexall("DeploymentRegion|AWS::Region", local.body))
}
