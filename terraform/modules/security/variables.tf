#####################################
# Security Module - Variables
#####################################

#####################################
# Required Variables
#####################################

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 32
    error_message = "Name prefix must be between 1 and 32 characters."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where security groups will be created"
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must be a valid VPC identifier starting with 'vpc-'."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (for VPC endpoint security group)"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

#####################################
# Application Configuration
#####################################

variable "application_port" {
  description = "Port on which the application listens"
  type        = number
  default     = 5001

  validation {
    condition     = var.application_port > 0 && var.application_port <= 65535
    error_message = "Application port must be between 1 and 65535."
  }
}

variable "rds_port" {
  description = "Port for RDS database (default: PostgreSQL)"
  type        = number
  default     = 5432

  validation {
    condition     = var.rds_port > 0 && var.rds_port <= 65535
    error_message = "RDS port must be between 1 and 65535."
  }
}

#####################################
# Bastion Configuration
#####################################

variable "enable_bastion" {
  description = "Enable bastion host security group (NOT RECOMMENDED: use SSM Session Manager instead)"
  type        = bool
  default     = false
}

variable "bastion_allowed_cidr" {
  description = "CIDR block allowed to SSH to bastion (if enabled)"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.bastion_allowed_cidr, 0))
    error_message = "Bastion allowed CIDR must be a valid IPv4 CIDR block."
  }
}

#####################################
# VPC Endpoints
#####################################

variable "enable_vpc_endpoint_sg" {
  description = "Create security group for VPC endpoints (SSM, ECR, etc.)"
  type        = bool
  default     = true
}

#####################################
# Custom Security Group
#####################################

variable "create_custom_sg" {
  description = "Create an additional custom security group"
  type        = bool
  default     = false
}

variable "custom_sg_description" {
  description = "Description for custom security group"
  type        = string
  default     = "Custom security group for additional services"
}

variable "custom_sg_ingress_rules" {
  description = "Map of ingress rules for custom security group"
  type = map(object({
    description = string
    cidr_ipv4   = optional(string)
    from_port   = number
    to_port     = number
    ip_protocol = string
  }))
  default = {}
}

variable "custom_sg_egress_rules" {
  description = "Map of egress rules for custom security group"
  type = map(object({
    description = string
    cidr_ipv4   = optional(string)
    from_port   = number
    to_port     = number
    ip_protocol = string
  }))
  default = {}
}

#####################################
# Tags
#####################################

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
