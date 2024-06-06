output "foo_vpc_id" {
  description = "Amazon EKS VPC ID"
  value       = module.foo_vpc.vpc_id
}

output "bar_vpc_id" {
  description = "Amazon EKS VPC ID"
  value       = module.bar_vpc.vpc_id
}

output "foo_subnet_ids" {
  description = "Amazon EKS Subnet IDs"
  value       = module.foo_vpc.private_subnets
}

output "bar_subnet_ids" {
  description = "Amazon EKS Subnet IDs"
  value       = module.bar_vpc.private_subnets
}

output "foo_vpc_cidr" {
  description = "Amazon EKS VPC CIDR Block."
  value       = local.foo_vpc_cidr
}

output "bar_vpc_cidr" {
  description = "Amazon EKS VPC CIDR Block."
  value       = local.bar_vpc_cidr
}

output "foo_private_route_table_ids" {
  description = "List of IDs of private route tables"
  value       = module.foo_vpc.private_route_table_ids
}

output "bar_private_route_table_ids" {
  description = "List of IDs of private route tables"
  value       = module.bar_vpc.private_route_table_ids
}

output "foo_additional_sg_id" {
  description = "foo cluster additional SG"
  value       = aws_security_group.foo_eks_cluster_additional_sg.id
}

output "bar_additional_sg_id" {
  description = "bar cluster additional SG"
  value       = aws_security_group.bar_eks_cluster_additional_sg.id
}