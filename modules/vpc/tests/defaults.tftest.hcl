# Tests for the vpc module.
#
# `command = plan` means these assert CONFIGURATION LOGIC only — subnet maths, NAT
# topology, tag propagation, toggles. No API calls, no credentials, no cost. See ADR-0004.

provider "aws" {
  region                      = "eu-central-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  name                 = "test"
  cidr_block           = "10.0.0.0/16"
  availability_zones   = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  tags                 = { Project = "aws-gitops-platform" }
  public_subnet_tags   = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags  = { "kubernetes.io/role/internal-elb" = "1" }
}

run "defaults_build_one_public_and_one_private_subnet_per_az" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3
    error_message = "Expected exactly one public and one private subnet per availability zone."
  }

  # Subnets are keyed by AZ, and each AZ gets the CIDR at the same index.
  assert {
    condition = (
      aws_subnet.public["eu-central-1b"].cidr_block == "10.0.1.0/24" &&
      aws_subnet.private["eu-central-1c"].cidr_block == "10.0.12.0/24"
    )
    error_message = "Subnet CIDRs must be zipped onto availability zones by index."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must NOT auto-assign public IPs — ALBs and NATs allocate their own."
  }

  # Every private subnet has its own route table (so NAT topology can change later
  # without re-associating subnets).
  assert {
    condition     = length(aws_route_table.private) == 3 && length(aws_route_table_association.private) == 3
    error_message = "Expected one private route table + association per AZ."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true && aws_vpc.this.enable_dns_support == true
    error_message = "DNS support + hostnames must be on — EKS private endpoints and RDS rely on them."
  }
}

run "defaults_use_a_single_shared_nat_gateway" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1
    error_message = "Default (enable_nat_gateway=true, single_nat_gateway=true) must create exactly one NAT + EIP."
  }

  assert {
    condition     = contains(keys(aws_nat_gateway.this), "eu-central-1a")
    error_message = "The single NAT gateway must live in the first availability zone."
  }

  # All three private route tables get a default route (all pointing at the one NAT).
  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "Every private subnet needs a 0.0.0.0/0 route when NAT is enabled."
  }
}

run "per_az_nat_when_single_nat_gateway_is_false" {
  command = plan

  variables {
    single_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_eip.nat) == 3
    error_message = "single_nat_gateway=false must create one NAT + EIP per availability zone."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "Every private subnet still needs exactly one default route."
  }
}

run "no_nat_resources_when_nat_is_disabled" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0
    error_message = "enable_nat_gateway=false must create no NAT gateways or EIPs (they are hourly cost)."
  }

  assert {
    condition     = length(aws_route.private_nat) == 0
    error_message = "Private subnets must have no 0.0.0.0/0 route when NAT is disabled."
  }

  # Public routing is unaffected by the NAT toggle.
  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "Public route table must still route 0.0.0.0/0 to the internet gateway."
  }
}

run "flow_logs_are_on_by_default_and_least_privilege" {
  command = plan

  assert {
    condition     = length(aws_flow_log.this) == 1 && length(aws_cloudwatch_log_group.flow) == 1
    error_message = "Flow logs must be enabled by default."
  }

  assert {
    condition     = aws_flow_log.this[0].traffic_type == "ALL"
    error_message = "Flow logs should capture ALL traffic by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow[0].retention_in_days == 30
    error_message = "Flow-log retention must default to 30 days — never 0 (infinite) on a budget."
  }

  # The publish policy's `resources` reference the log-group ARN, which is unknown at
  # plan time, so assert the parts that ARE known: the action set is the minimal three
  # (no logs:*), and only the flow-logs service may assume the role.
  assert {
    condition = toset(flatten([
      for s in data.aws_iam_policy_document.flow_publish[0].statement : s.actions
      ])) == toset([
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ])
    error_message = "Flow-log IAM policy must grant exactly the three publish actions — never logs:*."
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.flow_assume[0].json, "vpc-flow-logs.amazonaws.com")
    error_message = "Only vpc-flow-logs.amazonaws.com may assume the flow-logs role."
  }
}

run "flow_logs_can_be_disabled" {
  command = plan

  variables {
    enable_flow_logs = false
  }

  assert {
    condition = (
      length(aws_flow_log.this) == 0 &&
      length(aws_cloudwatch_log_group.flow) == 0 &&
      length(aws_iam_role.flow) == 0
    )
    error_message = "enable_flow_logs=false must create no flow-log resources (log group, role, flow log)."
  }

  assert {
    condition     = output.flow_log_group_name == null
    error_message = "flow_log_group_name output must be null when flow logs are disabled."
  }
}

run "tags_propagate_and_tier_tags_land_on_the_right_subnets" {
  command = plan

  assert {
    condition = (
      aws_vpc.this.tags["Project"] == "aws-gitops-platform" &&
      aws_vpc.this.tags["Name"] == "test" &&
      aws_subnet.private["eu-central-1a"].tags["Project"] == "aws-gitops-platform"
    )
    error_message = "Common tags (plus Name) must propagate to the VPC and subnets."
  }

  assert {
    condition = (
      aws_subnet.public["eu-central-1a"].tags["kubernetes.io/role/elb"] == "1" &&
      !contains(keys(aws_subnet.public["eu-central-1a"].tags), "kubernetes.io/role/internal-elb")
    )
    error_message = "public_subnet_tags must land on public subnets only."
  }

  assert {
    condition = (
      aws_subnet.private["eu-central-1a"].tags["kubernetes.io/role/internal-elb"] == "1" &&
      !contains(keys(aws_subnet.private["eu-central-1a"].tags), "kubernetes.io/role/elb")
    )
    error_message = "private_subnet_tags must land on private subnets only."
  }

  assert {
    condition = (
      aws_subnet.public["eu-central-1a"].tags["Tier"] == "public" &&
      aws_subnet.private["eu-central-1a"].tags["Tier"] == "private"
    )
    error_message = "Each subnet must carry a Tier tag matching its role."
  }
}

run "rejects_mismatched_subnet_and_az_counts" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24"] # only two for three AZs
  }

  # The cross-variable check is a resource precondition (Terraform 1.5 compat).
  expect_failures = [aws_vpc.this]
}

run "rejects_fewer_than_two_availability_zones" {
  command = plan

  variables {
    availability_zones   = ["eu-central-1a"]
    public_subnet_cidrs  = ["10.0.0.0/24"]
    private_subnet_cidrs = ["10.0.10.0/24"]
  }

  expect_failures = [var.availability_zones]
}

run "rejects_an_invalid_cidr" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/33"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_an_unsupported_retention_period" {
  command = plan

  variables {
    flow_log_retention_days = 45
  }

  expect_failures = [var.flow_log_retention_days]
}
