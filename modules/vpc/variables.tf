variable "name" {
  description = "Name prefix for every resource in the VPC (also the `Name` tag)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 2-31 chars, lowercase alphanumeric or hyphens, starting with a letter."
  }
}

variable "cidr_block" {
  description = "IPv4 CIDR for the VPC. Use a /16 to leave headroom for subnet carving."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR (e.g. 10.0.0.0/16)."
  }
}

variable "availability_zones" {
  description = <<-EOT
    Availability zones to spread subnets across. One public and one private subnet is
    created per AZ, so `public_subnet_cidrs` and `private_subnet_cidrs` must have the
    same length as this list. Two AZs is the minimum EKS accepts; three is the usual
    production choice.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability_zones are required — single-AZ VPCs are not HA and EKS rejects them."
  }
}

variable "public_subnet_cidrs" {
  description = "One CIDR per AZ for the public subnets (ALB, NAT gateways). Must be inside cidr_block."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "One CIDR per AZ for the private subnets (EKS nodes, RDS). Must be inside cidr_block."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Create NAT gateway(s) so private subnets can reach the internet (image pulls, AWS APIs).
    NAT is HOURLY + per-GB and NOT free-tier — roughly $32/month per gateway. Disable for
    LocalStack (not implemented there) or when private subnets only need VPC endpoints.
  EOT
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = <<-EOT
    When true, provision ONE NAT gateway (in the first AZ) shared by all private subnets.
    Cheaper, but a single point of failure for egress — the dev-environment trade-off.
    Set false for one NAT per AZ (the production pattern, N× the hourly cost).
  EOT
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Ship VPC Flow Logs to CloudWatch Logs. On by default — network visibility is cheap insurance."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for flow logs. 0 = never expire (not recommended for a portfolio budget)."
  type        = number
  default     = 30

  validation {
    # The fixed set of retention values CloudWatch Logs accepts.
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be one of the retention periods CloudWatch Logs supports."
  }
}

variable "flow_log_traffic_type" {
  description = "Which traffic to capture in flow logs: ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "public_subnet_tags" {
  description = <<-EOT
    Extra tags for public subnets only. The usual reason is Kubernetes subnet discovery,
    e.g. { "kubernetes.io/role/elb" = "1" } so the AWS Load Balancer Controller places
    internet-facing ALBs here.
  EOT
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = <<-EOT
    Extra tags for private subnets only, e.g. { "kubernetes.io/role/internal-elb" = "1" }
    and "kubernetes.io/cluster/<name>" = "shared" for EKS node placement.
  EOT
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
