#####################################
# RDS Module - Variables
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

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets are required for high availability."
  }
}

variable "vpc_security_group_ids" {
  description = "List of VPC security group IDs to associate with the RDS instance"
  type        = list(string)

  validation {
    condition     = length(var.vpc_security_group_ids) > 0
    error_message = "At least one security group is required."
  }
}

#####################################
# Database Configuration
#####################################

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "appdb"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "master_username" {
  description = "Master username for the database (default: dbadmin)"
  type        = string
  default     = ""

  validation {
    condition     = var.master_username == "" || can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.master_username))
    error_message = "Master username must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "port" {
  description = "Port on which the database accepts connections"
  type        = number
  default     = 5432

  validation {
    condition     = var.port > 0 && var.port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

#####################################
# Engine Configuration
#####################################

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15"
}

variable "parameter_group_family" {
  description = "Parameter group family (e.g., postgres15)"
  type        = string
  default     = "postgres15"
}

variable "major_engine_version" {
  description = "Major engine version for option group"
  type        = string
  default     = "15"
}

#####################################
# Instance Configuration
#####################################

variable "instance_class" {
  description = "Instance class for the RDS instance"
  type        = string
  default     = "db.t3.small"

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "Instance class must start with 'db.'."
  }
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "max_allocated_storage" {
  description = "Maximum storage for autoscaling (0 to disable)"
  type        = number
  default     = 100

  validation {
    condition     = var.max_allocated_storage == 0 || var.max_allocated_storage >= 20
    error_message = "Max allocated storage must be 0 (disabled) or >= 20 GB."
  }
}

variable "storage_type" {
  description = "Storage type (gp2, gp3, io1, io2)"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "Storage type must be gp2, gp3, io1, or io2."
  }
}

variable "iops" {
  description = "IOPS for io1/io2 storage (ignored for gp2/gp3)"
  type        = number
  default     = null
}

#####################################
# High Availability
#####################################

variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability"
  type        = bool
  default     = true
}

variable "availability_zone" {
  description = "Availability zone (only for single AZ deployment)"
  type        = string
  default     = null
}

#####################################
# Backup Configuration
#####################################

variable "backup_retention_period" {
  description = "Number of days to retain automated backups (0 to disable)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "backup_window" {
  description = "Preferred backup window (UTC)"
  type        = string
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]-([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.backup_window))
    error_message = "Backup window must be in format HH:MM-HH:MM."
  }
}

variable "maintenance_window" {
  description = "Preferred maintenance window (UTC)"
  type        = string
  default     = "sun:04:00-sun:05:00"

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "Maintenance window must be in format ddd:HH:MM-ddd:HH:MM."
  }
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying (NOT recommended for production)"
  type        = bool
  default     = false
}

variable "delete_automated_backups" {
  description = "Delete automated backups immediately after instance deletion"
  type        = bool
  default     = true
}

#####################################
# Encryption
#####################################

variable "create_kms_key" {
  description = "Create a new KMS key for RDS encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "ARN of existing KMS key (if create_kms_key is false)"
  type        = string
  default     = null
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

#####################################
# Monitoring
#####################################

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch (postgresql, upgrade)"
  type        = list(string)
  default     = ["postgresql", "upgrade"]

  validation {
    condition     = alltrue([for log in var.enabled_cloudwatch_logs_exports : contains(["postgresql", "upgrade"], log)])
    error_message = "Valid log types are: postgresql, upgrade."
  }
}

variable "enabled_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0, 1, 5, 10, 15, 30, 60)"
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.enabled_monitoring_interval)
    error_message = "Monitoring interval must be 0, 1, 5, 10, 15, 30, or 60 seconds."
  }
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days (7 or 731)"
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention must be 7 or 731 days."
  }
}

variable "performance_insights_kms_key_id" {
  description = "ARN of KMS key for Performance Insights encryption"
  type        = string
  default     = null
}

#####################################
# Parameter Group Settings
#####################################

variable "max_connections" {
  description = "Maximum number of database connections"
  type        = number
  default     = 100

  validation {
    condition     = var.max_connections > 0 && var.max_connections <= 5000
    error_message = "Max connections must be between 1 and 5000."
  }
}

variable "log_min_duration_statement" {
  description = "Log queries taking longer than this (milliseconds, -1 to disable)"
  type        = number
  default     = 1000
}

variable "custom_parameters" {
  description = "Additional custom database parameters"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

#####################################
# Option Group
#####################################

variable "create_option_group" {
  description = "Create a DB option group"
  type        = bool
  default     = false
}

#####################################
# Protection Settings
#####################################

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply changes immediately (not during maintenance window)"
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades"
  type        = bool
  default     = true
}

#####################################
# CloudWatch Alarms
#####################################

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for the database"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}

variable "alarm_cpu_threshold" {
  description = "CPU utilization threshold for alarms (percentage)"
  type        = number
  default     = 80

  validation {
    condition     = var.alarm_cpu_threshold > 0 && var.alarm_cpu_threshold <= 100
    error_message = "CPU threshold must be between 0 and 100."
  }
}

variable "alarm_free_storage_threshold" {
  description = "Free storage threshold for alarms (bytes)"
  type        = number
  default     = 5368709120 # 5 GB in bytes
}

variable "alarm_free_memory_threshold" {
  description = "Free memory threshold for alarms (bytes)"
  type        = number
  default     = 268435456 # 256 MB in bytes
}

#####################################
# Tags
#####################################

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
