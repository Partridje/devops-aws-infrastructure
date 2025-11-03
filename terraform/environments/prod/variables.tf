#####################################
# Production Environment - Variables
#####################################

#####################################
# Project Configuration
#####################################

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "demo-app"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

#####################################
# Network Configuration
#####################################

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.1.0.0/16"
}

#####################################
# Application Configuration
#####################################

variable "application_port" {
  description = "Port on which application listens"
  type        = number
  default     = 5001
}

variable "app_version" {
  description = "Application version tag"
  type        = string
  default     = "1.0.0"
}

variable "ecr_repository_url" {
  description = "ECR repository URL for Docker images"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS"
  type        = string
  default     = ""
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS-1-2-2017-01"
}

variable "enable_https_redirect" {
  description = "Redirect HTTP to HTTPS (only works if certificate_arn is provided)"
  type        = bool
  default     = false
}

#####################################
# Database Configuration
#####################################

variable "database_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "appdb"
}

variable "rds_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

#####################################
# Monitoring Configuration
#####################################

variable "alert_email_addresses" {
  description = "Email addresses to receive alerts"
  type        = list(string)
  default     = []
}

#####################################
# WAF Configuration
#####################################

variable "waf_rate_limit" {
  description = "Maximum requests from single IP in 5 minutes"
  type        = number
  default     = 2000
}

variable "waf_ip_whitelist" {
  description = "List of IP addresses to whitelist (CIDR notation)"
  type        = list(string)
  default     = []
}

variable "waf_blocked_countries" {
  description = "List of country codes to block (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = []
}

variable "waf_excluded_rules" {
  description = "List of AWS Managed Rules to exclude (count mode)"
  type        = list(string)
  default     = []
}

variable "waf_blocked_requests_threshold" {
  description = "Threshold for WAF blocked requests alarm"
  type        = number
  default     = 1000
}
