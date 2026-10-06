# VPC: multi-AZ public + private subnets, optional NAT (single or per-AZ), optional
# VPC Flow Logs to CloudWatch, and a locked-down default security group.
#
# LOCAL FIDELITY NOTE: LocalStack Community only *accepts* VPC/subnet/route API calls —
# nothing actually routes. This module is `plan`/`validate`-only on the $0 path
# (see the root README fidelity table). It is fully real on the guarded AWS path.

locals {
  # True when every AZ has exactly one public and one private CIDR. The user-facing
  # error for a mismatch is the precondition on aws_vpc.this; this flag just stops
  # zipmap()/indexing from crashing first with a less helpful message.
  inputs_consistent = (
    length(var.public_subnet_cidrs) == length(var.availability_zones) &&
    length(var.private_subnet_cidrs) == length(var.availability_zones)
  )

  # Key every subnet by its AZ name so for_each addresses are stable and readable:
  # aws_subnet.public["eu-central-1a"] rather than aws_subnet.public[0].
  public_subnets  = local.inputs_consistent ? zipmap(var.availability_zones, var.public_subnet_cidrs) : {}
  private_subnets = local.inputs_consistent ? zipmap(var.availability_zones, var.private_subnet_cidrs) : {}

  # NAT topology. single_nat_gateway = one gateway in the first AZ shared by every
  # private subnet (cheap, one egress SPOF). Otherwise one per AZ (prod pattern).
  nat_azs = var.enable_nat_gateway && local.inputs_consistent ? (
    var.single_nat_gateway ? [var.availability_zones[0]] : var.availability_zones
  ) : []

  # Which NAT gateway each private subnet's route table points at.
  private_nat_az = {
    for az in var.availability_zones :
    az => var.single_nat_gateway ? var.availability_zones[0] : az
  }

  tags = merge(var.tags, { Name = var.name })
}

# --- VPC ----------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true # required for EKS private endpoint + RDS hostnames
  tags                 = local.tags

  lifecycle {
    # Cross-variable checks live here (not in `validation`) so the module stays
    # compatible with Terraform 1.5, which cannot reference other vars in validation.
    precondition {
      condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
      error_message = "public_subnet_cidrs must have exactly one CIDR per availability zone."
    }
    precondition {
      condition     = length(var.private_subnet_cidrs) == length(var.availability_zones)
      error_message = "private_subnet_cidrs must have exactly one CIDR per availability zone."
    }
    precondition {
      condition     = length(distinct(concat(var.public_subnet_cidrs, var.private_subnet_cidrs))) == length(var.availability_zones) * 2
      error_message = "Subnet CIDRs must be unique across public and private subnets."
    }
  }
}

# The default SG is created implicitly with allow-all egress and intra-SG ingress.
# Adopting it with zero rules means nothing accidentally placed in it can talk.
# (Checkov CKV2_AWS_12 / Trivy AWS-0104.)
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-default-deny-all" })
}

# --- Internet gateway + public subnets ------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = local.tags
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  # Deliberately FALSE: nothing in a public subnet should get a public IP by default.
  # ALBs and NAT gateways allocate their own addresses explicitly. (Trivy AWS-0164.)
  map_public_ip_on_launch = false

  tags = merge(var.tags, var.public_subnet_tags, {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# --- NAT gateways (optional, $$) -----------------------------------------------

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# --- Private subnets ------------------------------------------------------------

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = merge(var.tags, var.private_subnet_tags, {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  })
}

# One route table per private subnet even in single-NAT mode, so flipping
# single_nat_gateway later is a route change, not a subnet re-association.
resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = var.enable_nat_gateway ? local.private_subnets : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.private_nat_az[each.key]].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# --- VPC Flow Logs → CloudWatch (optional) ---------------------------------------

# CloudWatch log group. SSE with the CloudWatch-managed key by default; a CMK is the
# same accepted-but-deferred non-goal as the state bucket (see ADR-0001 rationale).
# 1-year retention (CKV_AWS_338) is a compliance posture, not a portfolio one — the
# retention is a tunable input and the default is chosen for cost.
#trivy:ignore:AWS-0017 exp:2027-02-01
resource "aws_cloudwatch_log_group" "flow" {
  #checkov:skip=CKV_AWS_158:CMK encryption is a documented non-goal (ADR-0001); CloudWatch-managed SSE is in place.
  #checkov:skip=CKV_AWS_338:Retention is a tunable input; 30-day default is a deliberate cost choice for a non-regulated workload.
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days
  tags              = local.tags
}

data "aws_iam_policy_document" "flow_assume" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

# Least privilege: only the actions the flow-logs service needs, scoped to this one
# log group (and its streams) rather than "logs:*" on "*".
data "aws_iam_policy_document" "flow_publish" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    sid = "PublishFlowLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.flow[0].arn,
      "${aws_cloudwatch_log_group.flow[0].arn}:*",
    ]
  }
}

resource "aws_iam_role" "flow" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_assume[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "flow" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "publish-flow-logs"
  role   = aws_iam_role.flow[0].id
  policy = data.aws_iam_policy_document.flow_publish[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_log_traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow[0].arn
  iam_role_arn             = aws_iam_role.flow[0].arn
  max_aggregation_interval = 60 # seconds; 600 is the cheaper default, 60 is far more useful for debugging
  tags                     = local.tags
}
