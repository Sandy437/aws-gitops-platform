output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR of the VPC (for security-group rules that scope to in-VPC traffic)."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs, ordered to match `availability_zones`. Feed to ALB / NAT placement."
  value       = [for az in var.availability_zones : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs, ordered to match `availability_zones`. Feed to EKS node groups and RDS subnet groups."
  value       = [for az in var.availability_zones : aws_subnet.private[az].id]
}

output "public_subnets_by_az" {
  description = "Map of AZ name → public subnet ID."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnets_by_az" {
  description = "Map of AZ name → private subnet ID."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "nat_gateway_public_ips" {
  description = "Elastic IPs of the NAT gateway(s) — the egress addresses to allowlist downstream. Empty when NAT is disabled."
  value       = [for az in local.nat_azs : aws_eip.nat[az].public_ip]
}

output "private_route_table_ids" {
  description = "Private route table IDs (one per AZ), e.g. for adding VPC endpoint routes."
  value       = [for az in var.availability_zones : aws_route_table.private[az].id]
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC Flow Logs, or null when flow logs are disabled."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow[0].name : null
}
