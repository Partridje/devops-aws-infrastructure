#####################################
# SSM Module Outputs
#####################################

output "app_version_parameter_name" {
  description = "Name of the SSM parameter containing application version"
  value       = aws_ssm_parameter.app_version.name
}

output "app_version_parameter_arn" {
  description = "ARN of the SSM parameter containing application version"
  value       = aws_ssm_parameter.app_version.arn
}
