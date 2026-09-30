# Guards on the CloudFormation template itself. No provider calls: the helper
# module only reads the file.

variables {
  # The full set of value/content actions both read-only roles must deny. A
  # change here is a change to what B.O.R.I.S can read, so it is reviewed as one.
  expected_deny_actions = [
    "s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTorrent", "s3:GetObjectVersionTorrent",
    "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:GetParameterHistory",
    "dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query", "dynamodb:Scan",
    "dynamodb:PartiQLSelect", "dynamodb:GetRecords", "dynamodb:ExportTableToPointInTime",
    "secretsmanager:GetSecretValue", "secretsmanager:BatchGetSecretValue",
    "kinesis:GetRecords", "kinesis:SubscribeToShard",
    "rds-data:ExecuteStatement", "rds-data:BatchExecuteStatement", "rds-data:ExecuteSql",
    "redshift-data:ExecuteStatement", "redshift-data:BatchExecuteStatement",
    "redshift-data:GetStatementResult", "redshift-data:GetStatementResultV2",
    "redshift:GetClusterCredentials", "redshift:GetClusterCredentialsWithIAM", "redshift-serverless:GetCredentials",
    "athena:GetQueryResults", "athena:GetQueryResultsStream",
    "es:ESHttpGet", "es:ESHttpPost", "aoss:APIAccessAll",
    "timestream:Select",
    "cassandra:Select",
    "neptune-db:ReadDataViaQuery",
    "qldb:SendCommand", "qldb:PartiQLSelect", "qldb:GetRevision", "qldb:GetBlock",
    "appconfig:GetConfiguration", "appconfigdata:StartConfigurationSession", "appconfigdata:GetLatestConfiguration",
    "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
    "glacier:GetJobOutput", "glacier:InitiateJob",
    "ec2:GetPasswordData",
    "logs:Unmask",
    "sdb:Select",
  ]
}

run "template_facts" {
  command = apply

  module {
    source = "./tests/template_facts"
  }

  variables {
    template_path = "templates/boris-ai.yaml"
  }

  # The management-account role and the member-account role carry duplicated
  # YAML; the two copies must deny exactly the same set.
  assert {
    condition     = length(output.deny_blocks) == 2
    error_message = "Expected exactly 2 DenyDataPlaneReads statements (management + member role), found ${length(output.deny_blocks)}."
  }

  assert {
    condition     = output.deny_blocks[0] == output.deny_blocks[1]
    error_message = "The two DenyDataPlaneReads copies have drifted: management=${jsonencode(output.deny_blocks[0])} member=${jsonencode(output.deny_blocks[1])}."
  }

  assert {
    condition     = output.deny_blocks[0] == sort(var.expected_deny_actions)
    error_message = "Deny action set mismatch: got ${jsonencode(output.deny_blocks[0])}, want ${jsonencode(sort(var.expected_deny_actions))}."
  }

  # Management read-only, member read-only, data management. Nothing else.
  assert {
    condition     = output.iam_role_count == 3
    error_message = "Expected 3 IAM roles in the template, found ${output.iam_role_count}."
  }

  assert {
    condition     = length(output.forbidden_actions) == 0
    error_message = "The template grants actions it must not: ${jsonencode(output.forbidden_actions)}. SQS, EventBridge and Cost Explorer writes were removed; Cost Explorer reads come from ReadOnlyAccess."
  }

  assert {
    condition     = output.data_role_mentions_outside_data_stackset == 0
    error_message = "The data management role appears outside the data StackSet and the outputs; it must exist in the data account only."
  }

  assert {
    condition     = output.data_role_mentions_in_data_stackset > 0
    error_message = "The data StackSet no longer creates boris-ai-resources-management-role, the exact name registration requires."
  }

  assert {
    condition     = output.data_stackset_is_conditional && output.data_stackset_auto_deployment_off && output.data_stackset_pinned_to_account
    error_message = "The data StackSet must be conditional on DataStorageAccountId, have auto-deployment off, and target that one account (INTERSECTION) so an OU move cannot remove it."
  }

  assert {
    condition     = !output.version_placeholder_left
    error_message = "The template still carries {{RELEASE_VERSION}}; substitute the release version."
  }

  # The region is an input, never an output: one Region holds every StackSet instance.
  assert {
    condition     = output.region_allowed == ["eu-central-1", "us-east-1"]
    error_message = "Region AllowedValues drifted from the module's region validation: ${jsonencode(output.region_allowed)}."
  }

  assert {
    condition     = output.readonly_stackset_regions == "!Ref Region" && output.data_stackset_regions == "!Ref Region"
    error_message = "StackSet regions: read-only=${output.readonly_stackset_regions} data=${output.data_stackset_regions}; want Region for both."
  }

  assert {
    condition     = output.split_region_mentions == 0
    error_message = "The template still mentions VendorRegion or DataRegion; both are folded into Region."
  }

  assert {
    condition     = output.region_outputs == 0
    error_message = "The template exposes a region (DeploymentRegion or AWS::Region); regions come from the module, not the stack."
  }

  # CloudFormation's inline template_body limit.
  assert {
    condition     = output.size_bytes <= 51200
    error_message = "The template is ${output.size_bytes} bytes, over the 51,200-byte template_body limit."
  }
}
