# Plan-only tests against a mocked AWS provider: no credentials, no API calls.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }

  mock_data "aws_organizations_organization" {
    defaults = {
      id                = "o-abcde12345"
      master_account_id = "111111111111"
      roots             = [{ id = "r-ab12", arn = "arn:aws:organizations::111111111111:root/o-abcde12345/r-ab12", name = "Root", policy_types = [] }]
      non_master_accounts = [
        { id = "222222222222", arn = "", email = "", name = "data", status = "ACTIVE", state = "ACTIVE", joined_method = "", joined_timestamp = "" },
        { id = "333333333333", arn = "", email = "", name = "workloads", status = "ACTIVE", state = "ACTIVE", joined_method = "", joined_timestamp = "" },
      ]
    }
  }
}

variables {
  vendor_aws_account_id = "999999999999"
  region                = "eu-central-1"
  external_id           = "123e4567-e89b-12d3-a456-426614174000"
  active_regions        = ["us-east-1", "eu-central-1", "us-east-1"]
  connection_secret     = "boris_abcdefghijklmnop_abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
}

run "primary_org_sends_all_data_fields" {
  command = plan

  variables {
    data_account_id       = "222222222222"
    registration_endpoint = "https://install.example.com/"
  }

  assert {
    condition = jsondecode(local.registration_body) == {
      management_account_id       = "111111111111"
      readonly_role_name          = "boris-ai-readonly"
      active_regions              = "eu-central-1,us-east-1"
      vendor_region               = "eu-central-1"
      org_deployment_region       = "eu-central-1"
      management_account_role_arn = "arn:aws:iam::111111111111:role/boris-ai-readonly"
      data_account_id             = "222222222222"
      data_management_role_arn    = "arn:aws:iam::222222222222:role/boris-ai-resources-management-role"
    }
    error_message = "Unexpected primary registration body: ${local.registration_body}"
  }

  assert {
    condition     = aws_cloudformation_stack.boris_ai.parameters["DataStorageAccountId"] == "222222222222"
    error_message = "The data account must reach the template."
  }

  assert {
    condition     = aws_cloudformation_stack.boris_ai.parameters["Region"] == "eu-central-1" && length(setintersection(keys(aws_cloudformation_stack.boris_ai.parameters), ["VendorRegion", "DataRegion"])) == 0
    error_message = "The template must receive region as its one Region parameter."
  }

  assert {
    condition     = aws_cloudformation_stack.boris_ai.parameters["OrganizationalUnitIds"] == "r-ab12" && aws_cloudformation_stack.boris_ai.parameters["OrganizationRootId"] == "r-ab12"
    error_message = "With no OUs given, the read-only StackSet must target the organization root."
  }

  # Every body field must be a trigger, or changing it would silently not re-register.
  assert {
    condition     = alltrue([for k, v in jsondecode(local.registration_body) : terraform_data.register[0].triggers_replace[k] == v])
    error_message = "Every registration body field must appear in triggers_replace with the same value."
  }

  assert {
    condition     = terraform_data.register[0].triggers_replace["endpoint"] == "https://install.example.com" && terraform_data.register[0].triggers_replace["organization_id"] == "o-abcde12345"
    error_message = "The endpoint (trailing slash trimmed) and organization must be triggers."
  }

  assert {
    condition     = !strcontains(jsonencode(terraform_data.register[0].triggers_replace), "boris_")
    error_message = "The connection secret must never be a trigger; triggers are persisted to state."
  }

  assert {
    condition     = output.registration_curl == "curl -X PUT 'https://install.example.com/aws/install/o-abcde12345' -H 'Content-Type: application/json' -H \"Authorization: Bearer $BORIS_CONNECTION_SECRET\" -d '${local.registration_body}'"
    error_message = "Unexpected registration_curl: ${output.registration_curl}"
  }
}

run "us_east_1_region_reaches_every_field" {
  command = plan

  variables {
    region          = "us-east-1"
    data_account_id = "222222222222"
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  assert {
    condition     = jsondecode(local.registration_body)["vendor_region"] == "us-east-1" && jsondecode(local.registration_body)["org_deployment_region"] == "us-east-1"
    error_message = "vendor_region and org_deployment_region must both be region: ${local.registration_body}"
  }

  # The data fields are the account and role only; the data lives in region.
  assert {
    condition     = !contains(keys(jsondecode(local.registration_body)), "data_region") && contains(keys(jsondecode(local.registration_body)), "data_account_id") && contains(keys(jsondecode(local.registration_body)), "data_management_role_arn")
    error_message = "A primary must send data_account_id and data_management_role_arn and no data_region: ${local.registration_body}"
  }

  assert {
    condition     = aws_cloudformation_stack.boris_ai.parameters["Region"] == "us-east-1"
    error_message = "The template's Region must follow region."
  }
}

run "secondary_org_sends_no_data_fields" {
  command = plan

  variables {
    target_organizational_unit_ids = ["ou-ab12-zzzzzzzz", "ou-ab12-aaaaaaaa", "ou-ab12-zzzzzzzz"]
  }

  assert {
    condition     = length(setintersection(keys(jsondecode(local.registration_body)), ["data_account_id", "data_management_role_arn", "data_region"])) == 0
    error_message = "A secondary organization must send none of the data fields: ${local.registration_body}"
  }

  assert {
    condition     = aws_cloudformation_stack.boris_ai.parameters["DataStorageAccountId"] == "" && aws_cloudformation_stack.boris_ai.parameters["Region"] == "eu-central-1"
    error_message = "A secondary organization passes an empty DataStorageAccountId, which skips the data StackSet, and still passes Region."
  }

  assert {
    condition     = jsondecode(local.registration_body)["vendor_region"] == "eu-central-1" && jsondecode(local.registration_body)["org_deployment_region"] == "eu-central-1"
    error_message = "A secondary organization still sends region as vendor_region and org_deployment_region: ${local.registration_body}"
  }

  assert {
    condition     = aws_cloudformation_stack.boris_ai.parameters["OrganizationalUnitIds"] == "ou-ab12-aaaaaaaa,ou-ab12-zzzzzzzz"
    error_message = "Explicit OUs must be passed sorted and deduplicated."
  }

  assert {
    condition     = output.data_management_role_arn == null
    error_message = "A secondary organization has no data management role."
  }
}

run "defaults_self_register_with_fixed_names" {
  command = plan

  assert {
    condition     = length(terraform_data.register) == 1 && terraform_data.register[0].triggers_replace["endpoint"] == "https://install.getboris.ai"
    error_message = "Self-registration must be on by default, against https://install.getboris.ai."
  }

  # B.O.R.I.S reads the stack and assumes the role by these exact names.
  assert {
    condition     = aws_cloudformation_stack.boris_ai.name == "BorisAI" && aws_cloudformation_stack.boris_ai.parameters["ReadOnlyRoleName"] == "boris-ai-readonly" && output.management_account_role_arn == "arn:aws:iam::111111111111:role/boris-ai-readonly"
    error_message = "The stack must be BorisAI and the read-only role boris-ai-readonly."
  }
}

run "manual_registration_needs_no_secret" {
  command = plan

  variables {
    enable_self_registration = false
    connection_secret        = ""
  }

  assert {
    condition     = length(terraform_data.register) == 0 && startswith(output.registration_curl, "curl -X PUT 'https://install.getboris.ai/aws/install/o-abcde12345' ")
    error_message = "With self-registration off, nothing is sent and registration_curl targets the default endpoint: ${output.registration_curl}"
  }
}

run "eks_rbac_manifest_grants_only_named_reads" {
  command = plan

  assert {
    condition     = output.eks_kubernetes_groups == ["boris-readonly"]
    error_message = "Unexpected eks_kubernetes_groups: ${jsonencode(output.eks_kubernetes_groups)}"
  }

  assert {
    condition     = [for d in split("\n---\n", output.eks_rbac_manifest) : "${yamldecode(d).kind}/${yamldecode(d).metadata.name}"] == ["ClusterRole/boris-readonly", "ClusterRoleBinding/boris-readonly"]
    error_message = "The manifest must hold exactly the boris-readonly ClusterRole and ClusterRoleBinding."
  }

  assert {
    condition = { for r in yamldecode(split("\n---\n", output.eks_rbac_manifest)[0]).rules : one(r.apiGroups) => r.resources } == {
      ""                             = ["nodes", "persistentvolumes"]
      "storage.k8s.io"               = ["storageclasses"]
      "rbac.authorization.k8s.io"    = ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
      "admissionregistration.k8s.io" = ["mutatingwebhookconfigurations", "validatingwebhookconfigurations"]
      "elbv2.k8s.aws"                = ["targetgroupbindings"]
      "eks.amazonaws.com"            = ["targetgroupbindings"]
      "vpcresources.k8s.aws"         = ["securitygrouppolicies"]
      "crd.k8s.amazonaws.com"        = ["eniconfigs"]
      "karpenter.sh"                 = ["nodepools"]
      "gateway.networking.k8s.io"    = ["gateways", "httproutes"]
    }
    error_message = "The ClusterRole's resources drifted from the reviewed set."
  }

  assert {
    condition     = alltrue([for r in yamldecode(split("\n---\n", output.eks_rbac_manifest)[0]).rules : r.verbs == ["get", "list"] && length(keys(r)) == 3])
    error_message = "Every rule must grant get and list only, with no resourceNames or nonResourceURLs."
  }

  assert {
    condition     = length(setintersection(flatten([for r in yamldecode(split("\n---\n", output.eks_rbac_manifest)[0]).rules : concat(r.apiGroups, r.resources, r.verbs)]), ["*", "watch", "secrets", "configmaps", "external-secrets.io", "ec2nodeclasses"])) == 0
    error_message = "The ClusterRole must not grant a wildcard, watch, Secrets, ConfigMaps, the External Secrets kinds or EC2NodeClasses."
  }

  assert {
    condition = yamldecode(split("\n---\n", output.eks_rbac_manifest)[1]) == {
      apiVersion = "rbac.authorization.k8s.io/v1"
      kind       = "ClusterRoleBinding"
      metadata   = { name = "boris-readonly" }
      roleRef    = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "boris-readonly" }
      subjects   = [{ apiGroup = "rbac.authorization.k8s.io", kind = "Group", name = "boris-readonly" }]
    }
    error_message = "The ClusterRoleBinding must bind the boris-readonly ClusterRole to the boris-readonly group only."
  }
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

run "rejects_region_outside_allowed" {
  command = plan

  variables {
    region = "us-west-2"
  }

  expect_failures = [var.region]
}

run "rejects_availability_zone_as_region" {
  command = plan

  variables {
    region = "eu-central-1a"
  }

  expect_failures = [var.region]
}

run "rejects_malformed_data_account" {
  command = plan

  variables {
    data_account_id = "22222222222"
  }

  expect_failures = [var.data_account_id]
}

run "rejects_malformed_vendor_account" {
  command = plan

  variables {
    vendor_aws_account_id = "not-an-account"
  }

  expect_failures = [var.vendor_aws_account_id]
}

run "rejects_malformed_ou" {
  command = plan

  variables {
    target_organizational_unit_ids = ["ou-ab12"]
  }

  expect_failures = [var.target_organizational_unit_ids]
}

run "rejects_shell_metacharacter_in_region" {
  command = plan

  variables {
    active_regions = ["us-east-1'; id; '"]
  }

  expect_failures = [var.active_regions]
}

run "rejects_non_uuid_external_id" {
  command = plan

  variables {
    external_id = "not-a-customer-id"
  }

  expect_failures = [var.external_id]
}

run "rejects_truncated_secret" {
  command = plan

  variables {
    connection_secret = "boris_abcdefghijklmnop_short"
  }

  expect_failures = [var.connection_secret]
}

run "rejects_missing_secret_by_default" {
  command = plan

  variables {
    connection_secret = ""
  }

  expect_failures = [var.connection_secret]
}

run "rejects_empty_endpoint" {
  command = plan

  variables {
    registration_endpoint = ""
  }

  expect_failures = [var.registration_endpoint]
}

# ---------------------------------------------------------------------------
# Preconditions against the organization
# ---------------------------------------------------------------------------

run "rejects_data_account_equal_to_management" {
  command = plan

  variables {
    data_account_id = "111111111111"
  }

  expect_failures = [aws_cloudformation_stack.boris_ai]
}

run "rejects_data_account_outside_org" {
  command = plan

  variables {
    data_account_id = "444444444444"
  }

  expect_failures = [aws_cloudformation_stack.boris_ai]
}

run "rejects_provider_outside_region" {
  command = plan

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  expect_failures = [aws_cloudformation_stack.boris_ai]
}

run "rejects_non_management_credentials" {
  command = plan

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "333333333333"
    }
  }

  expect_failures = [aws_cloudformation_stack.boris_ai]
}
