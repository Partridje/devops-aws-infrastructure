#####################################
# Security Module - Outputs
#####################################

#####################################
# ALB Security Group
#####################################

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "alb_security_group_arn" {
  description = "ARN of the ALB security group"
  value       = aws_security_group.alb.arn
}

output "alb_security_group_name" {
  description = "Name of the ALB security group"
  value       = aws_security_group.alb.name
}

#####################################
# Application Security Group
#####################################

output "application_security_group_id" {
  description = "ID of the application security group"
  value       = aws_security_group.application.id
}

output "application_security_group_arn" {
  description = "ARN of the application security group"
  value       = aws_security_group.application.arn
}

output "application_security_group_name" {
  description = "Name of the application security group"
  value       = aws_security_group.application.name
}

#####################################
# RDS Security Group
#####################################

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "rds_security_group_arn" {
  description = "ARN of the RDS security group"
  value       = aws_security_group.rds.arn
}

output "rds_security_group_name" {
  description = "Name of the RDS security group"
  value       = aws_security_group.rds.name
}

#####################################
# Bastion Security Group
#####################################

output "bastion_security_group_id" {
  description = "ID of the bastion security group (if enabled)"
  value       = var.enable_bastion ? aws_security_group.bastion[0].id : null
}

output "bastion_security_group_arn" {
  description = "ARN of the bastion security group (if enabled)"
  value       = var.enable_bastion ? aws_security_group.bastion[0].arn : null
}

output "bastion_security_group_name" {
  description = "Name of the bastion security group (if enabled)"
  value       = var.enable_bastion ? aws_security_group.bastion[0].name : null
}

#####################################
# VPC Endpoints Security Group
#####################################

output "vpc_endpoints_security_group_id" {
  description = "ID of the VPC endpoints security group (if enabled)"
  value       = var.enable_vpc_endpoint_sg ? aws_security_group.vpc_endpoints[0].id : null
}

output "vpc_endpoints_security_group_arn" {
  description = "ARN of the VPC endpoints security group (if enabled)"
  value       = var.enable_vpc_endpoint_sg ? aws_security_group.vpc_endpoints[0].arn : null
}

output "vpc_endpoints_security_group_name" {
  description = "Name of the VPC endpoints security group (if enabled)"
  value       = var.enable_vpc_endpoint_sg ? aws_security_group.vpc_endpoints[0].name : null
}

#####################################
# Custom Security Group
#####################################

output "custom_security_group_id" {
  description = "ID of the custom security group (if created)"
  value       = var.create_custom_sg ? aws_security_group.custom[0].id : null
}

output "custom_security_group_arn" {
  description = "ARN of the custom security group (if created)"
  value       = var.create_custom_sg ? aws_security_group.custom[0].arn : null
}

output "custom_security_group_name" {
  description = "Name of the custom security group (if created)"
  value       = var.create_custom_sg ? aws_security_group.custom[0].name : null
}

#####################################
# All Security Group IDs
#####################################

output "all_security_group_ids" {
  description = "Map of all security group IDs"
  value = {
    alb           = aws_security_group.alb.id
    application   = aws_security_group.application.id
    rds           = aws_security_group.rds.id
    bastion       = var.enable_bastion ? aws_security_group.bastion[0].id : null
    vpc_endpoints = var.enable_vpc_endpoint_sg ? aws_security_group.vpc_endpoints[0].id : null
    custom        = var.create_custom_sg ? aws_security_group.custom[0].id : null
  }
}
