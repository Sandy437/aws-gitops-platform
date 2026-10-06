# Module: `vpc`

A multi-AZ VPC with one public and one private subnet per availability zone, an internet
gateway, optional NAT (single shared or one-per-AZ), optional VPC Flow Logs to CloudWatch,
and a default security group adopted with **zero rules**.

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name               = "gitops-dev"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]

  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]

  # dev: one shared NAT. prod: single_nat_gateway = false for one per AZ.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Subnet discovery tags for EKS + the AWS Load Balancer Controller.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  tags = {
    Project = "aws-gitops-platform"
    Env     = "dev"
  }
}
```

## Design notes

- **Subnets are keyed by AZ**, not index (`aws_subnet.private["eu-central-1a"]`). Adding
  or removing an AZ changes only that AZ's resources instead of shifting every index.
- **One private route table per AZ, always.** Even in single-NAT mode. Flipping
  `single_nat_gateway` later is a route change, not a subnet re-association.
- **`map_public_ip_on_launch = false` on public subnets.** ALBs and NAT gateways allocate
  their own addresses; nothing should get a public IP by accident.
- **Default SG is adopted with no rules.** Anything accidentally placed in it can't talk.
- **Flow-log IAM is scoped** to the one log group (three actions, no `logs:*`, no `*`).
- Cross-variable checks (CIDR list lengths vs AZs) are **resource preconditions**, not
  `validation` blocks, so the module stays usable on Terraform 1.5.

## 💸 Cost toggles

| Input | Default | Cost note |
|-------|---------|-----------|
| `enable_nat_gateway` | `true` | NAT is **hourly + per-GB, not free-tier** (~$32/month each). |
| `single_nat_gateway` | `true` | One shared NAT (cheap, egress SPOF). `false` = one per AZ, N× cost. |
| `enable_flow_logs` | `true` | CloudWatch ingest + storage; small at portfolio scale. |
| `flow_log_retention_days` | `30` | Never `0` (infinite) on a budget. |

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `name` | Name prefix / `Name` tag for every resource | `string` | — (required) |
| `cidr_block` | VPC IPv4 CIDR | `string` | `"10.0.0.0/16"` |
| `availability_zones` | AZs to span (≥ 2) | `list(string)` | — (required) |
| `public_subnet_cidrs` | One CIDR per AZ | `list(string)` | — (required) |
| `private_subnet_cidrs` | One CIDR per AZ | `list(string)` | — (required) |
| `enable_nat_gateway` | Create NAT gateway(s) | `bool` | `true` |
| `single_nat_gateway` | One shared NAT vs one per AZ | `bool` | `true` |
| `enable_flow_logs` | Ship VPC Flow Logs to CloudWatch | `bool` | `true` |
| `flow_log_retention_days` | CloudWatch retention (must be a value CloudWatch accepts) | `number` | `30` |
| `flow_log_traffic_type` | `ACCEPT`, `REJECT` or `ALL` | `string` | `"ALL"` |
| `public_subnet_tags` | Extra tags for public subnets only | `map(string)` | `{}` |
| `private_subnet_tags` | Extra tags for private subnets only | `map(string)` | `{}` |
| `tags` | Tags applied to every resource | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR (for in-VPC SG rules) |
| `public_subnet_ids` | Public subnet IDs, ordered like `availability_zones` |
| `private_subnet_ids` | Private subnet IDs, ordered like `availability_zones` |
| `public_subnets_by_az` | Map AZ → public subnet ID |
| `private_subnets_by_az` | Map AZ → private subnet ID |
| `nat_gateway_public_ips` | NAT EIPs (egress addresses); empty when NAT disabled |
| `private_route_table_ids` | Private route table IDs (for VPC endpoint routes) |
| `flow_log_group_name` | Flow-log CloudWatch group, or `null` when disabled |

## Tests

`tests/defaults.tftest.hcl` — 11 `plan`-mode runs covering subnet maths, NAT topology
(single / per-AZ / off), flow-log toggle + least-privilege IAM, tag propagation, and four
negative cases for input validation. No credentials, no cost:

```bash
tofu -chdir=modules/vpc init -backend=false && tofu -chdir=modules/vpc test
```

## Local fidelity (LocalStack)

LocalStack Community **accepts** the VPC/subnet/route/NAT API calls but implements no real
networking, and does not implement flow logs. On the $0 path this module is therefore
`plan`/`validate`-only — see the fidelity table in the root README. It is fully real on the
guarded AWS path.
