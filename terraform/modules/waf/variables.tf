#####################################
# WAF Module - Variables
#####################################

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "alb_arn" {
  description = "ARN of the Application Load Balancer to protect"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

#####################################
# Rate Limiting
#####################################

variable "rate_limit" {
  description = "Maximum number of requests from a single IP in 5 minutes"
  type        = number
  default     = 2000
}

#####################################
# IP Management
#####################################

variable "ip_whitelist" {
  description = "List of IP addresses to whitelist (CIDR notation)"
  type        = list(string)
  default     = []
}

variable "blocked_countries" {
  description = "List of country codes to block (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = []
}

#####################################
# Rule Customization
#####################################

variable "excluded_rules" {
  description = "List of AWS Managed Rules to exclude (count mode instead of block)"
  type        = list(string)
  default     = []
}

#####################################
# Logging
#####################################

variable "enable_logging" {
  description = "Enable WAF logging to CloudWatch"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

#####################################
# Monitoring
#####################################

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for WAF metrics"
  type        = bool
  default     = true
}

variable "blocked_requests_threshold" {
  description = "Threshold for blocked requests alarm"
  type        = number
  default     = 1000
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}

#####################################
# Tags
#####################################

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
