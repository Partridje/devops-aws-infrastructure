#####################################
# VPC Module - Variables
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

variable "vpc_cidr" {
  description = "CIDR block for VPC"
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

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
}

#####################################
# Optional Variables
#####################################

variable "azs_count" {
  description = "Number of Availability Zones to use (will use minimum of this and available AZs)"
  type        = number
  default     = 3

  validation {
    condition     = var.azs_count >= 2 && var.azs_count <= 6
    error_message = "AZ count must be between 2 and 6 for high availability."
  }
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all AZs (cost optimization, reduces HA)"
  type        = bool
  default     = false
}

#####################################
# VPC Flow Logs
#####################################

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for network traffic analysis"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain VPC Flow Logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_logs_retention_days)
    error_message = "Flow logs retention must be a valid CloudWatch Logs retention value."
  }
}

variable "flow_logs_traffic_type" {
  description = "Type of traffic to log (ACCEPT, REJECT, or ALL)"
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "Flow logs traffic type must be ACCEPT, REJECT, or ALL."
  }
}

#####################################
# VPC Endpoints
#####################################

variable "enable_s3_endpoint" {
  description = "Enable S3 VPC endpoint (gateway endpoint, no additional cost)"
  type        = bool
  default     = true
}

variable "enable_dynamodb_endpoint" {
  description = "Enable DynamoDB VPC endpoint (gateway endpoint, no additional cost)"
  type        = bool
  default     = true
}

#####################################
# Network ACLs
#####################################

variable "manage_default_network_acl" {
  description = "Manage the default Network ACL with Terraform"
  type        = bool
  default     = false
}

#####################################
# DHCP Options
#####################################

variable "enable_dhcp_options" {
  description = "Enable custom DHCP options for the VPC"
  type        = bool
  default     = false
}

variable "dhcp_options_domain_name" {
  description = "DNS domain name for DHCP options (default: region.compute.internal)"
  type        = string
  default     = ""
}

variable "dhcp_options_domain_name_servers" {
  description = "List of DNS servers for DHCP options"
  type        = list(string)
  default     = ["AmazonProvidedDNS"]

  validation {
    condition     = length(var.dhcp_options_domain_name_servers) > 0
    error_message = "At least one DNS server must be specified."
  }
}

#####################################
# Tags
#####################################

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
