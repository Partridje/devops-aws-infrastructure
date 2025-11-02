#####################################
# Development Environment - Variables
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
  default     = "dev"
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
  default     = "10.0.0.0/16"
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
  default     = "latest"
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
