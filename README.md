# B.O.R.I.S — AWS onboarding Terraform module

Terraform you run in your own AWS organization's management account to grant
B.O.R.I.S read-only access across the organization, and — in exactly one
organization — the data access it needs in your dedicated data account.

You apply it with your own credentials; B.O.R.I.S never receives them. By
default `apply` then registers the organization with B.O.R.I.S, telling it which
organization, roles and regions to use; a one-line manual registration call is
the alternative.

> **Before you start:** registration is authenticated, so you need a
> `connection_secret` issued by the B.O.R.I.S team, one per organization. Plan
> fails without it unless you set `enable_self_registration = false`. Ask for
> yours before you apply — see [The connection secret](#the-connection-secret).

## What it creates

One CloudFormation stack in the management account, named `BorisAI`. It
holds:

- A **read-only role** in the management account (`boris-ai-readonly`).
- A **read-only StackSet** that creates the same role in every account of the
  organizational units you target (the organization root by default), including
  accounts added to those OUs later.
- In your **primary organization only**, a **data StackSet** that creates
  `boris-ai-resources-management-role` in your data account and nowhere else.

Every role trusts only the B.O.R.I.S account in your install details and
requires your customer ID as the `sts:ExternalId`. The stack and read-only role
names are fixed, not inputs: B.O.R.I.S finds the stack and assumes the role by
those names.

### Region

`region` is where B.O.R.I.S stores your data: `eu-central-1` or `us-east-1`, as
given in your install details, and the same in every organization you register.
The module requires its `aws` provider to be configured for it: the stack and
every StackSet instance, the data role's included, are created there. IAM is
global, so the roles work in every region either way.

### Read scope

The read-only role carries `ReadOnlyAccess`, `SecurityAudit`, and the EKS
Kubernetes-API and EKS MCP read actions. Cost Explorer reads come from
`ReadOnlyAccess`. Nothing outside the data account can create, change or delete
anything: there are no SQS, EventBridge or Cost Explorer write permissions in
this template.

An explicit **deny on data-plane reads** overrides those allows. Resource
metadata stays readable; the contents do not. It covers S3 object bodies, SSM
parameter values, DynamoDB items and exports, Secrets Manager values, Kinesis
records, the RDS and Redshift Data APIs, Redshift credential minting, Athena
results, OpenSearch documents, Timestream, Keyspaces, Neptune, QLDB, AppConfig
payloads, ECR image layers, Glacier retrieval, EC2 password data, CloudWatch Logs
unmasking and SimpleDB. The full list is in
[`templates/boris-ai.yaml`](templates/boris-ai.yaml), in both role definitions,
and a test keeps the two copies identical.

`ReadOnlyAccess` is an AWS-managed policy that AWS widens over time, and the deny
list only blocks what it names. Some metadata carries secrets anyway — Lambda
environment variables and EC2 user data, for example. If that matters in your
organization, add a deny for it in your own SCP or permission boundary.

### The data account

`data_account_id` names the member account where B.O.R.I.S keeps your data. It
gets `boris-ai-resources-management-role` with DynamoDB and S3 full access and S3
Vectors access, scoped to that one account.

The data role has its own StackSet instance, pinned to that account under the
organization root with auto-deployment off. Moving the data account between OUs,
or changing `target_organizational_unit_ids`, never removes it.

## Usage

### Primary organization

The organization that contains your data account. Register it first.

```hcl
provider "aws" {
  region = "eu-central-1" # must match region below
}

module "boris_aws" {
  source  = "sirob-tech/boris-ai/aws"
  version = "~> 1.0"

  vendor_aws_account_id = "111122223333" # from your B.O.R.I.S install details
  region                = "eu-central-1" # where B.O.R.I.S stores your data
  external_id           = "00000000-0000-0000-0000-000000000000" # your customer ID

  active_regions = ["eu-central-1", "us-east-1"]

  data_account_id = "444455556666"

  connection_secret = var.connection_secret # supply as TF_VAR_connection_secret
}
```

### Secondary organizations

Any further organization is registered with **no data account**. It gets read-only
roles only, and B.O.R.I.S keeps its data in the primary's data account.

```hcl
module "boris_aws" {
  source  = "sirob-tech/boris-ai/aws"
  version = "~> 1.0"

  vendor_aws_account_id = "111122223333"
  region                = "eu-central-1" # the same as the primary
  external_id           = "00000000-0000-0000-0000-000000000000"

  active_regions = ["us-east-1"]

  # Optional: target specific OUs instead of the whole organization.
  target_organizational_unit_ids = ["ou-ab12-11111111"]

  connection_secret = var.connection_secret # this organization's own secret
}
```

B.O.R.I.S refuses a secondary registration (`409`) until the primary is
registered. Each organization needs its own connection secret and its own
instance of this module, applied in that organization's management account.

### Registering

By default the module sends a `PUT` to
`https://install.getboris.ai/aws/install/<org_id>` inside `apply`, carrying the
organization, its roles, `active_regions` and `region`, plus the data account and
data role for a primary. B.O.R.I.S refuses a `region` that does not match your
install details. Every body field is a trigger, so changing any of them
re-registers on the next apply; an unchanged apply sends nothing.

To register by hand instead, set `enable_self_registration = false` (no
`connection_secret` input needed) and run the `registration_curl` output. Read
it with `terraform output -raw`, which prints it ready to run (plain
`terraform output` shows the quoted form, whose escaped `\"` would be sent
literally):

```
export BORIS_CONNECTION_SECRET='boris_...'
terraform output -raw register   # with: output "register" { value = module.boris_aws.registration_curl }
```

Editing an input updates the output, but nothing is sent until you run it again.

Self-registration retries 5xx, unexpected redirects and transport failures with
about four minutes of backoff. Any 4xx fails `apply` immediately: a refused
secret (401), a conflicting registration (409) or a rejected field (400) does not
clear on its own.

### Inputs worth knowing

| Variable | Default | Notes |
|---|---|---|
| `region` | required | Where B.O.R.I.S stores your data: `eu-central-1` or `us-east-1`. The provider region must match. See [Region](#region). |
| `active_regions` | required | Where you run workloads. Scopes what the memory scrape retains; it does not restrict what B.O.R.I.S reads. Sorted and deduplicated before sending. |
| `target_organizational_unit_ids` | `[]` (the root) | OU IDs (`ou-...`) or the root ID (`r-...`). |
| `data_account_id` | `null` | Primary organization only. Must be a member account, not the management account. |
| `connection_secret` | `""` | Required while `enable_self_registration` is on. See [The connection secret](#the-connection-secret). |
| `enable_self_registration` | `true` | `false` skips the in-apply `PUT`; run the `registration_curl` output instead. |
| `registration_endpoint` | `https://install.getboris.ai` | Change only if the B.O.R.I.S team gives you another. |

### The connection secret

The secret looks like `boris_<16 chars>_<52 chars>`. It authenticates
registration, and your customer identity is derived from it.

- **It is not single-use.** It binds to this organization on first use and stays
  valid, so keep it: a later apply that changes a registered value calls the
  endpoint again.
- **Keep it out of state.** Pass it as `TF_VAR_connection_secret`, not in a
  committed `.tfvars`. The module keeps it out of `triggers_replace`, hands it to
  `local-exec` only through the environment, and the `registration_curl` output
  references `$BORIS_CONNECTION_SECRET` rather than the value. A saved plan file
  does record it: treat plan artifacts as secret-bearing.

## Prerequisites

- Apply with credentials for the organization's **management account**. The
  StackSets use service-managed permissions called as `SELF`, which only works
  there; the module checks the caller account at plan time.
- **Trusted access for CloudFormation StackSets** must be enabled in AWS
  Organizations (CloudFormation console → StackSets → *Activate trusted access*).
- The deployer needs CloudFormation stack and StackSet permissions, IAM role
  creation in the management account, and `organizations:Describe*` /
  `organizations:List*`.

StackSet operations run through every targeted account (25% at a time, stopping
at the first failure), so a large organization can take a while. The stack
timeouts are 90 minutes.

## Adopting an existing `BorisAI` stack

If you installed B.O.R.I.S through the CloudFormation console link, adopt that
stack instead of creating a second one. Only the outer stack is imported; its
StackSets keep their identity.

1. **Inventory what is there.** In `region`, note the stack's parameters, and
   where its StackSet instances live:

   ```bash
   aws cloudformation describe-stacks --region <region> --stack-name BorisAI --query 'Stacks[0].Parameters'
   aws cloudformation list-stack-instances --region <region> --stack-set-name BorisAI \
     --query 'Summaries[].[Account,Region,OrganizationalUnitId]' --output table
   ```

   Set `target_organizational_unit_ids` to the OUs the instances cover. Use the
   same `external_id`, `vendor_aws_account_id` and data account. The stack must
   be named `BorisAI` and its `ReadOnlyRoleName` parameter `boris-ai-readonly`;
   if either differs, stop and contact the B.O.R.I.S team. Two region checks
   decide whether this is a plain adoption:

   - **The stack must be in `region`.** The module's provider is pinned there
     and cannot import a stack from another region. If yours lives elsewhere,
     stop and contact the B.O.R.I.S team: adopting it means recreating it, which
     deletes every role first.
   - **The instances should be in `region`** — the old `DeploymentRegion`
     parameter. If they are in another region, the update moves every read-only
     instance to `region`. That does not replace the StackSet, but because IAM
     is global, each member account's role is deleted and recreated (or the
     create collides with the role not yet deleted, and the StackSet operation
     fails). Contact the B.O.R.I.S team before applying.

2. **Import with self-registration off**: set `enable_self_registration = false`
   for now, then:

   ```bash
   terraform import 'module.boris_aws.aws_cloudformation_stack.boris_ai' BorisAI
   ```

3. **Read the plan.** It must be an in-place **update** of
   `aws_cloudformation_stack.boris_ai`. If it says *must be replaced*, stop: a
   replacement would delete every role.

4. **Preview the stack update as a change set**, then delete it:

   ```bash
   aws cloudformation create-change-set --stack-name BorisAI \
     --change-set-name boris-module-preview \
     --template-body file://.terraform/modules/boris_aws/templates/boris-ai.yaml \
     --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
     --parameters ParameterKey=VendorAccountId,ParameterValue=... # every parameter the plan shows
   aws cloudformation describe-change-set --stack-name BorisAI --change-set-name boris-module-preview
   aws cloudformation delete-change-set --stack-name BorisAI --change-set-name boris-module-preview
   ```

   Expect the management account's `resources-management` role and policy to be
   removed, the read-only StackSet to be modified, and a new data StackSet in
   `region`. The `DeploymentRegion` parameter is replaced by `Region`, and the
   `DeploymentRegion` outputs go: an in-place update, not a replacement of the
   stack or either StackSet. If anything imports the
   `BorisAI-DeploymentRegion` export, the update fails until that import is
   removed. A change set does not show per-account StackSet instance operations.

5. **Apply.** The read-only StackSet update removes the old
   `boris-ai-resources-management-role` from every member account, including the
   data account; the new data StackSet then recreates it there. B.O.R.I.S cannot
   write to your data account for the minutes in between, so pick a quiet window.

6. **Register once**: remove `enable_self_registration = false` and apply, or
   run the `registration_curl` output. The values match your existing registration, so
   B.O.R.I.S accepts it as a repeat.

7. Tell the B.O.R.I.S team, who confirm your organization collects cleanly.

## Offboarding

`terraform destroy` deletes the stack, its StackSets and every role they created,
which revokes all access. There is no deregistration endpoint: ask the B.O.R.I.S
team to revoke the connection and remove the registration.

Destroying a **primary** organization's module removes the data role, and
B.O.R.I.S can no longer reach your data. Destroying a secondary affects only that
organization.

## Versioning and upgrades

Pin a version:

```hcl
source  = "sirob-tech/boris-ai/aws"
version = "~> 1.0"
```

- **Major** — a change to review before adopting: a new permission, a removal
  from the deny list, or a breaking input change.
- **Minor** — new optional inputs, new outputs, additional guardrails.
- **Patch** — fixes and documentation.

The stack's `BorisAIVersion` output records the template version you applied.
Read the plan before every apply: the template diff is the authoritative record
of what changes in your organization.

## License

[Apache License 2.0](LICENSE). Apache-2.0 §6 grants no trademark rights: forks
are welcome, but must not be distributed under the B.O.R.I.S name.
