#####################################
# EC2 Module - Variables
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

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must be a valid VPC identifier."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least 2 public subnets required for ALB."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EC2 instances"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets required for high availability."
  }
}

variable "alb_security_group_ids" {
  description = "List of security group IDs for ALB"
  type        = list(string)

  validation {
    condition     = length(var.alb_security_group_ids) > 0
    error_message = "At least one security group required for ALB."
  }
}

variable "application_security_group_ids" {
  description = "List of security group IDs for application instances"
  type        = list(string)

  validation {
    condition     = length(var.application_security_group_ids) > 0
    error_message = "At least one security group required for instances."
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

variable "ssm_parameter_name" {
  description = "Name of SSM parameter containing application version"
  type        = string
}

variable "ssm_parameter_arn" {
  description = "ARN of SSM parameter containing application version"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for Docker image (optional)"
  type        = string
  default     = ""
}

variable "db_secret_arn" {
  description = "ARN of database credentials secret in Secrets Manager"
  type        = string
  default     = ""
}

variable "db_master_secret_arn" {
  description = "ARN of AWS-managed master password secret in Secrets Manager"
  type        = string
  default     = ""
}

variable "rds_kms_key_arn" {
  description = "ARN of KMS key used for RDS encryption"
  type        = string
  default     = ""
}

variable "custom_user_data" {
  description = "Additional user data script to append"
  type        = string
  default     = ""
}

#####################################
# EC2 Instance Configuration
#####################################

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.", var.instance_type))
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "ami_id" {
  description = "AMI ID to use (default: latest Amazon Linux 2023)"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 16384
    error_message = "Root volume size must be between 8 and 16384 GB."
  }
}

variable "root_volume_type" {
  description = "Type of root EBS volume (gp2, gp3, io1, io2)"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "Volume type must be gp2, gp3, io1, or io2."
  }
}

variable "root_volume_iops" {
  description = "IOPS for io1/io2 volumes"
  type        = number
  default     = null
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring (1-minute intervals)"
  type        = bool
  default     = false
}

variable "enable_ecr_access" {
  description = "Grant IAM permissions to pull images from ECR"
  type        = bool
  default     = true
}

#####################################
# Auto Scaling Group
#####################################

variable "asg_min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 2

  validation {
    condition     = var.asg_min_size >= 0 && var.asg_min_size <= 100
    error_message = "ASG min size must be between 0 and 100."
  }
}

variable "asg_max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 4

  validation {
    condition     = var.asg_max_size >= 1 && var.asg_max_size <= 100
    error_message = "ASG max size must be between 1 and 100."
  }
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 2

  validation {
    condition     = var.asg_desired_capacity >= 0 && var.asg_desired_capacity <= 100
    error_message = "ASG desired capacity must be between 0 and 100."
  }
}

variable "health_check_grace_period" {
  description = "Time in seconds after instance launch before health checks start"
  type        = number
  default     = 300

  validation {
    condition     = var.health_check_grace_period >= 0 && var.health_check_grace_period <= 3600
    error_message = "Health check grace period must be between 0 and 3600 seconds."
  }
}

#####################################
# Auto Scaling Policies
#####################################

variable "enable_cpu_scaling" {
  description = "Enable CPU-based target tracking scaling"
  type        = bool
  default     = true
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for scaling"
  type        = number
  default     = 70

  validation {
    condition     = var.cpu_target_value > 0 && var.cpu_target_value <= 100
    error_message = "CPU target value must be between 0 and 100."
  }
}

variable "enable_alb_scaling" {
  description = "Enable ALB request count target tracking scaling"
  type        = bool
  default     = false
}

variable "alb_requests_per_target" {
  description = "Target number of ALB requests per instance"
  type        = number
  default     = 1000
}

variable "enable_simple_scaling" {
  description = "Enable simple scaling policies with CloudWatch alarms"
  type        = bool
  default     = false
}

#####################################
# Load Balancer Configuration
#####################################

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = true
}

variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.alb_idle_timeout >= 1 && var.alb_idle_timeout <= 4000
    error_message = "ALB idle timeout must be between 1 and 4000 seconds."
  }
}

variable "enable_alb_access_logs" {
  description = "Enable ALB access logs to S3"
  type        = bool
  default     = false
}

variable "alb_access_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  type        = string
  default     = ""
}

variable "alb_access_logs_prefix" {
  description = "S3 prefix for ALB access logs"
  type        = string
  default     = "alb-logs"
}

#####################################
# Target Group Configuration
#####################################

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 2

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 2

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

variable "health_check_matcher" {
  description = "HTTP status codes for successful health checks"
  type        = string
  default     = "200"
}

variable "deregistration_delay" {
  description = "Time for connection draining before deregistration (seconds)"
  type        = number
  default     = 30

  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "Deregistration delay must be between 0 and 3600 seconds."
  }
}

variable "enable_stickiness" {
  description = "Enable session stickiness"
  type        = bool
  default     = false
}

variable "stickiness_duration" {
  description = "Stickiness duration in seconds"
  type        = number
  default     = 86400

  validation {
    condition     = var.stickiness_duration >= 1 && var.stickiness_duration <= 604800
    error_message = "Stickiness duration must be between 1 and 604800 seconds."
  }
}

#####################################
# HTTPS Configuration
#####################################

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS (empty to disable HTTPS)"
  type        = string
  default     = ""
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS-1-2-2017-01"
}

variable "enable_https_redirect" {
  description = "Redirect HTTP to HTTPS"
  type        = bool
  default     = false
}

#####################################
# Monitoring
#####################################

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch value."
  }
}

variable "create_monitoring_alarms" {
  description = "Create CloudWatch monitoring alarms"
  type        = bool
  default     = true
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
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
