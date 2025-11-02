#####################################
# Monitoring Module - Variables
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

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

#####################################
# SNS Configuration
#####################################

variable "alert_email_addresses" {
  description = "List of email addresses to receive alarm notifications"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All email addresses must be valid."
  }
}

#####################################
# Resource Identifiers
#####################################

variable "alb_arn" {
  description = "ARN of the Application Load Balancer"
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (for metrics)"
  type        = string
  default     = ""
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the target group"
  type        = string
  default     = ""
}

variable "asg_name" {
  description = "Name of the Auto Scaling Group"
  type        = string
  default     = ""
}

variable "db_instance_id" {
  description = "ID of the RDS instance"
  type        = string
  default     = ""
}

variable "application_log_group_name" {
  description = "Name of the application CloudWatch log group"
  type        = string
  default     = ""
}

#####################################
# Custom Metrics
#####################################

variable "custom_namespace" {
  description = "Custom CloudWatch namespace for application metrics"
  type        = string
  default     = ""
}

#####################################
# Log Alarms
#####################################

variable "enable_log_alarms" {
  description = "Enable alarms based on log metric filters"
  type        = bool
  default     = true
}

variable "error_rate_threshold" {
  description = "Threshold for error count alarm (errors per 5 minutes)"
  type        = number
  default     = 10

  validation {
    condition     = var.error_rate_threshold > 0
    error_message = "Error rate threshold must be greater than 0."
  }
}

#####################################
# Composite Alarms
#####################################

variable "enable_composite_alarms" {
  description = "Enable composite alarms for system health"
  type        = bool
  default     = false
}

variable "unhealthy_hosts_alarm_name" {
  description = "Name of the unhealthy hosts alarm (for composite alarm)"
  type        = string
  default     = ""
}

variable "rds_cpu_alarm_name" {
  description = "Name of the RDS CPU alarm (for composite alarm)"
  type        = string
  default     = ""
}

#####################################
# EventBridge
#####################################

variable "enable_eventbridge_rules" {
  description = "Enable EventBridge rules for state changes"
  type        = bool
  default     = true
}

#####################################
# Tags
#####################################

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
