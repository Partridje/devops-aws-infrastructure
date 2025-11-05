#####################################
# SSM Parameter Store
#####################################

# Application version parameter
# This parameter is updated by the app-deploy GitHub workflow
# EC2 instances read from this parameter to get current app version
resource "aws_ssm_parameter" "app_version" {
  name        = "/${var.project_name}/${var.environment}/app/version"
  description = "Current application version (Docker image tag)"
  type        = "String"
  value       = var.initial_app_version

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-version"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Allow updates from application deployment without Terraform detecting drift
  lifecycle {
    ignore_changes = [value]
  }
}
