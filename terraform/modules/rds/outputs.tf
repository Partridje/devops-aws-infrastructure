#####################################
# RDS Module - Outputs
#####################################

#####################################
# RDS Instance
#####################################

output "db_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "db_instance_endpoint" {
  description = "The connection endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_address" {
  description = "The hostname of the RDS instance"
  value       = aws_db_instance.main.address
}

output "db_instance_port" {
  description = "The port the database is listening on"
  value       = aws_db_instance.main.port
}

output "db_instance_name" {
  description = "The name of the database"
  value       = aws_db_instance.main.db_name
}

output "db_instance_username" {
  description = "The master username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "db_instance_engine" {
  description = "The database engine"
  value       = aws_db_instance.main.engine
}

output "db_instance_engine_version" {
  description = "The database engine version"
  value       = aws_db_instance.main.engine_version
}

output "db_instance_resource_id" {
  description = "The RDS Resource ID"
  value       = aws_db_instance.main.resource_id
}

output "db_instance_status" {
  description = "The RDS instance status"
  value       = aws_db_instance.main.status
}

output "db_instance_availability_zone" {
  description = "The availability zone of the instance"
  value       = aws_db_instance.main.availability_zone
}

output "db_instance_multi_az" {
  description = "Whether the instance is Multi-AZ"
  value       = aws_db_instance.main.multi_az
}

#####################################
# Secrets Manager
#####################################

# AWS-Managed Master Password Secret (contains ONLY the password)
output "master_user_secret_arn" {
  description = "ARN of the AWS-managed Secrets Manager secret containing master password (managed by RDS)"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
  sensitive   = true
}

output "master_user_secret_status" {
  description = "Status of the AWS-managed secret"
  value       = aws_db_instance.main.master_user_secret[0].secret_status
}

# Additional Connection Details Secret (contains host, port, username, etc.)
output "db_connection_secret_arn" {
  description = "ARN of the Secrets Manager secret containing full database connection details"
  value       = aws_secretsmanager_secret.db_connection_details.arn
  sensitive   = true
}

output "db_connection_secret_id" {
  description = "ID of the connection details secret"
  value       = aws_secretsmanager_secret.db_connection_details.id
  sensitive   = true
}

output "db_connection_secret_name" {
  description = "Name of the connection details secret"
  value       = aws_secretsmanager_secret.db_connection_details.name
  sensitive   = true
}

# Legacy output for backward compatibility (now points to connection details secret)
output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database connection details (use db_connection_secret_arn instead)"
  value       = aws_secretsmanager_secret.db_connection_details.arn
  sensitive   = true
}

output "db_secret_id" {
  description = "ID of the Secrets Manager secret (use db_connection_secret_id instead)"
  value       = aws_secretsmanager_secret.db_connection_details.id
  sensitive   = true
}

output "db_secret_name" {
  description = "Name of the Secrets Manager secret (use db_connection_secret_name instead)"
  value       = aws_secretsmanager_secret.db_connection_details.name
  sensitive   = true
}

#####################################
# KMS
#####################################

output "kms_key_id" {
  description = "The ID of the KMS key used for encryption"
  value       = var.create_kms_key ? aws_kms_key.rds[0].id : var.kms_key_id
}

output "kms_key_arn" {
  description = "The ARN of the KMS key used for encryption"
  value       = var.create_kms_key ? aws_kms_key.rds[0].arn : var.kms_key_id
}

#####################################
# Subnet Group
#####################################

output "db_subnet_group_id" {
  description = "The ID of the DB subnet group"
  value       = aws_db_subnet_group.main.id
}

output "db_subnet_group_arn" {
  description = "The ARN of the DB subnet group"
  value       = aws_db_subnet_group.main.arn
}

output "db_subnet_group_name" {
  description = "The name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}

#####################################
# Parameter Group
#####################################

output "db_parameter_group_id" {
  description = "The ID of the DB parameter group"
  value       = aws_db_parameter_group.main.id
}

output "db_parameter_group_arn" {
  description = "The ARN of the DB parameter group"
  value       = aws_db_parameter_group.main.arn
}

output "db_parameter_group_name" {
  description = "The name of the DB parameter group"
  value       = aws_db_parameter_group.main.name
}

#####################################
# Option Group
#####################################

output "db_option_group_id" {
  description = "The ID of the DB option group (if created)"
  value       = var.create_option_group ? aws_db_option_group.main[0].id : null
}

output "db_option_group_arn" {
  description = "The ARN of the DB option group (if created)"
  value       = var.create_option_group ? aws_db_option_group.main[0].arn : null
}

#####################################
# Monitoring
#####################################

output "enhanced_monitoring_role_arn" {
  description = "ARN of the enhanced monitoring IAM role"
  value       = var.enabled_monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null
}

output "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled"
  value       = aws_db_instance.main.performance_insights_enabled
}

#####################################
# CloudWatch Alarms
#####################################

output "cloudwatch_alarm_cpu_id" {
  description = "ID of the CPU utilization CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.database_cpu[0].id : null
}

output "cloudwatch_alarm_storage_id" {
  description = "ID of the free storage CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.database_storage[0].id : null
}

output "cloudwatch_alarm_memory_id" {
  description = "ID of the free memory CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.database_memory[0].id : null
}

output "cloudwatch_alarm_connections_id" {
  description = "ID of the database connections CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.database_connections[0].id : null
}

#####################################
# Connection Information
#####################################

output "connection_string" {
  description = "PostgreSQL connection string (use with credentials from Secrets Manager)"
  value       = "postgresql://${local.master_username}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.database_name}"
  sensitive   = true
}

output "connection_parameters" {
  description = "Map of connection parameters"
  value = {
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    database = aws_db_instance.main.db_name
    username = local.master_username
    engine   = "postgres"
  }
  sensitive = true
}
