#####################################
# SSM Module Variables
#####################################

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "initial_app_version" {
  description = "Initial application version to set (will be updated by GitHub workflow)"
  type        = string
  default     = "initial"
}
