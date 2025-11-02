#####################################
# RDS Module - Main Configuration
#####################################
# Creates a production-ready RDS PostgreSQL instance with:
# - Multi-AZ deployment for high availability
# - Automated backups with configurable retention
# - Encryption at rest using KMS
# - Enhanced monitoring
# - Credentials stored in AWS Secrets Manager
# - Parameter and option groups for optimization
# - DB subnet group across multiple AZs
#####################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "rds"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  )

  # Generate database identifier
  db_identifier = "${var.name_prefix}-${var.environment}-db"

  # Generate master username if not provided
  master_username = var.master_username != "" ? var.master_username : "dbadmin"
}

#####################################
# Password Management Strategy
#####################################
# Using AWS RDS Managed Master Password feature:
# - Password is generated and managed entirely by AWS
# - Password NEVER appears in Terraform state (ephemeral)
# - Automatically stored in AWS Secrets Manager
# - Encrypted with KMS
# - Supports automatic rotation
#
# Benefits over random_password resource:
# 1. Password never stored in Terraform state (even encrypted)
# 2. AWS handles lifecycle and rotation
# 3. Better security posture for production
# 4. Meets compliance requirements (SOC2, PCI-DSS)
#####################################

#####################################
# Additional Secrets Manager Secret
#####################################
# Create an additional secret with full connection details
# This is separate from AWS-managed password secret
# Useful for applications that need host, port, dbname in one place

resource "aws_secretsmanager_secret" "db_connection_details" {
  name_prefix             = "${var.name_prefix}-${var.environment}-db-connection-"
  description             = "RDS connection details for ${local.db_identifier}"
  recovery_window_in_days = var.deletion_protection ? 30 : 0

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-db-connection-details"
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_connection_details" {
  secret_id = aws_secretsmanager_secret.db_connection_details.id

  # Reference the AWS-managed password secret ARN
  # Applications retrieve password from master_user_secret
  secret_string = jsonencode({
    username                 = local.master_username
    engine                   = "postgres"
    host                     = aws_db_instance.main.address
    port                     = aws_db_instance.main.port
    dbname                   = var.database_name
    dbInstanceIdentifier     = aws_db_instance.main.identifier
    masterUserSecretArn      = aws_db_instance.main.master_user_secret[0].secret_arn
    passwordRetrievalCommand = "aws secretsmanager get-secret-value --secret-id ${aws_db_instance.main.master_user_secret[0].secret_arn} --query SecretString --output text | jq -r .password"
  })

  depends_on = [aws_db_instance.main]
}

#####################################
# KMS Key for Encryption
#####################################
# Create KMS key for RDS encryption at rest

resource "aws_kms_key" "rds" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for RDS encryption - ${local.db_identifier}"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-rds-kms-key"
    }
  )
}

resource "aws_kms_alias" "rds" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.name_prefix}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds[0].key_id
}

#####################################
# DB Subnet Group
#####################################
# Defines which subnets RDS can use (across multiple AZs)

resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.name_prefix}-${var.environment}-"
  description = "Database subnet group for ${local.db_identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-db-subnet-group"
    }
  )
}

#####################################
# DB Parameter Group
#####################################
# Custom parameters for PostgreSQL optimization

resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.name_prefix}-${var.environment}-"
  family      = var.parameter_group_family
  description = "Custom parameter group for ${local.db_identifier}"

  # Enable query logging for development
  dynamic "parameter" {
    for_each = var.environment == "dev" ? [1] : []
    content {
      name  = "log_statement"
      value = "all"
    }
  }

  # Log slow queries (queries taking longer than this threshold)
  parameter {
    name  = "log_min_duration_statement"
    value = var.log_min_duration_statement
  }

  # Enable auto_explain for slow queries
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  # Connection settings
  parameter {
    name  = "max_connections"
    value = var.max_connections
  }

  # Memory settings
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/32768}"
  }

  # Additional custom parameters
  dynamic "parameter" {
    for_each = var.custom_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-db-parameter-group"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#####################################
# DB Option Group
#####################################
# Additional features and settings

resource "aws_db_option_group" "main" {
  count = var.create_option_group ? 1 : 0

  name_prefix              = "${var.name_prefix}-${var.environment}-"
  option_group_description = "Option group for ${local.db_identifier}"
  engine_name              = "postgres"
  major_engine_version     = var.major_engine_version

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-db-option-group"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#####################################
# Enhanced Monitoring IAM Role
#####################################
# Required for RDS Enhanced Monitoring

resource "aws_iam_role" "enhanced_monitoring" {
  count = var.enabled_monitoring_interval > 0 ? 1 : 0

  name_prefix = "${var.name_prefix}-rds-enhanced-monitoring-"
  description = "IAM role for RDS Enhanced Monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach the managed policy to the role
resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.enabled_monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

#####################################
# RDS Instance
#####################################
# Main PostgreSQL database instance

resource "aws_db_instance" "main" {
  # Instance identification
  identifier     = local.db_identifier
  engine         = "postgres"
  engine_version = var.engine_version

  # Instance size
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = var.storage_type
  iops              = var.storage_type == "io1" || var.storage_type == "io2" ? var.iops : null
  storage_encrypted = true
  kms_key_id        = var.create_kms_key ? aws_kms_key.rds[0].arn : var.kms_key_id

  # Database configuration
  db_name  = var.database_name
  username = local.master_username
  port     = var.port

  # AWS Managed Master Password (BEST PRACTICE)
  # Password is generated by AWS and stored in Secrets Manager
  # Password NEVER appears in Terraform state
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.create_kms_key ? aws_kms_key.rds[0].arn : var.kms_key_id

  # High Availability
  multi_az               = var.multi_az
  availability_zone      = var.multi_az ? null : var.availability_zone
  db_subnet_group_name   = aws_db_subnet_group.main.name
  publicly_accessible    = false
  vpc_security_group_ids = var.vpc_security_group_ids

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name    = var.create_option_group ? aws_db_option_group.main[0].name : null

  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.db_identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  delete_automated_backups  = var.delete_automated_backups

  # Monitoring
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  monitoring_interval                   = var.enabled_monitoring_interval
  monitoring_role_arn                   = var.enabled_monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled && var.create_kms_key ? aws_kms_key.rds[0].arn : var.performance_insights_kms_key_id
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  # Protection
  deletion_protection = var.deletion_protection
  apply_immediately   = var.apply_immediately

  # Auto minor version upgrades
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # Storage autoscaling
  max_allocated_storage = var.max_allocated_storage

  # License model (for PostgreSQL, it's postgresql-license)
  license_model = "postgresql-license"

  tags = merge(
    local.common_tags,
    {
      Name = local.db_identifier
    }
  )

  lifecycle {
    ignore_changes = [
      # Ignore final snapshot identifier (contains timestamp)
      final_snapshot_identifier,
    ]
  }

  depends_on = [
    aws_db_parameter_group.main,
    aws_db_subnet_group.main
  ]
}

#####################################
# CloudWatch Alarms
#####################################
# Monitor database health and performance

resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.db_identifier}-high-cpu"
  alarm_description   = "Database CPU utilization is too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.db_identifier}-low-storage"
  alarm_description   = "Database free storage space is low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_free_storage_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "database_memory" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.db_identifier}-low-memory"
  alarm_description   = "Database freeable memory is low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.alarm_free_memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.db_identifier}-high-connections"
  alarm_description   = "Database connection count is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.max_connections * 0.8
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}
