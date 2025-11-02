#####################################
# Production Environment
#####################################
# This configuration creates a production-ready environment
# with high availability, monitoring, and security features
#####################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "Engineering"
      Owner       = "DevOps"
      Compliance  = "PCI-DSS"
    }
  }
}

# Get current AWS account info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#####################################
# Local Variables
#####################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

#####################################
# VPC Module
#####################################

module "vpc" {
  source = "../../modules/vpc"

  name_prefix = local.name_prefix
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  aws_region  = var.aws_region

  # Use 3 AZs for high availability
  azs_count = 3

  # NAT Gateway per AZ for high availability
  single_nat_gateway = false

  # VPC Flow Logs
  enable_flow_logs         = true
  flow_logs_retention_days = 30

  # VPC Endpoints
  enable_s3_endpoint       = true
  enable_dynamodb_endpoint = true

  tags = local.common_tags
}

#####################################
# Security Groups Module
#####################################

module "security" {
  source = "../../modules/security"

  name_prefix = local.name_prefix
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = module.vpc.vpc_cidr_block

  # Application configuration
  application_port = var.application_port
  rds_port         = var.rds_port

  # Enable VPC endpoints security group
  enable_vpc_endpoint_sg = true

  # Bastion disabled (use SSM Session Manager)
  enable_bastion = false

  tags = local.common_tags
}

#####################################
# RDS Module
#####################################

module "rds" {
  source = "../../modules/rds"

  name_prefix = local.name_prefix
  environment = var.environment

  # Network configuration
  subnet_ids             = module.vpc.database_subnet_ids
  vpc_security_group_ids = [module.security.rds_security_group_id]

  # Database configuration
  database_name = var.database_name

  # Instance configuration (production-sized)
  instance_class        = "db.t3.small"
  allocated_storage     = 100
  max_allocated_storage = 1000
  storage_type          = "gp3"

  # High availability enabled
  multi_az = true

  # Backup configuration
  backup_retention_period  = 30
  skip_final_snapshot      = false
  delete_automated_backups = false

  # Monitoring (full monitoring)
  enabled_monitoring_interval           = 60
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  # Protection enabled
  deletion_protection = true

  # Parameters
  max_connections            = 200
  log_min_duration_statement = 500

  custom_parameters = [
    {
      name  = "work_mem"
      value = "16384"
    },
    {
      name  = "maintenance_work_mem"
      value = "2097151"
    }
  ]

  # Alarms
  create_cloudwatch_alarms     = true
  alarm_actions                = [module.monitoring.sns_topic_arn]
  alarm_cpu_threshold          = 80
  alarm_free_storage_threshold = 10737418240 # 10GB

  tags = local.common_tags
}

#####################################
# EC2 Module (ALB + ASG)
#####################################

module "ec2" {
  source = "../../modules/ec2"

  name_prefix = local.name_prefix
  environment = var.environment
  vpc_id      = module.vpc.vpc_id

  # Network configuration
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Security groups
  alb_security_group_ids         = [module.security.alb_security_group_id]
  application_security_group_ids = [module.security.application_security_group_id]

  # Application configuration
  application_port   = var.application_port
  app_version        = var.app_version
  ecr_repository_url = var.ecr_repository_url
  db_secret_arn      = module.rds.db_secret_arn

  # Instance configuration
  instance_type              = "t3.small"
  root_volume_size           = 30
  root_volume_type           = "gp3"
  enable_detailed_monitoring = true

  # Auto Scaling
  asg_min_size         = 2
  asg_max_size         = 10
  asg_desired_capacity = 4

  # Scaling policies
  enable_cpu_scaling      = true
  cpu_target_value        = 70
  enable_alb_scaling      = true
  alb_requests_per_target = 1000

  # Load Balancer
  enable_deletion_protection = true
  alb_idle_timeout           = 60
  certificate_arn            = var.certificate_arn
  enable_https_redirect      = var.certificate_arn != ""

  # Health checks
  health_check_path              = "/health"
  health_check_interval          = 30
  health_check_healthy_threshold = 2
  health_check_grace_period      = 300
  deregistration_delay           = 30

  # Monitoring
  create_monitoring_alarms = true
  alarm_actions            = [module.monitoring.sns_topic_arn]
  log_retention_days       = 30

  tags = local.common_tags

  depends_on = [module.rds]
}

#####################################
# Monitoring Module
#####################################

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix = local.name_prefix
  environment = var.environment
  aws_region  = var.aws_region

  # Email alerts
  alert_email_addresses = var.alert_email_addresses

  # Resource identifiers
  alb_arn                    = module.ec2.alb_arn
  alb_arn_suffix             = module.ec2.alb_arn_suffix
  target_group_arn_suffix    = module.ec2.target_group_arn_suffix
  asg_name                   = module.ec2.asg_name
  db_instance_id             = module.rds.db_instance_id
  application_log_group_name = module.ec2.cloudwatch_log_group_name

  # Custom metrics
  custom_namespace = "Production/${var.project_name}"

  # Monitoring configuration
  enable_log_alarms          = true
  error_rate_threshold       = 5
  enable_composite_alarms    = true
  unhealthy_hosts_alarm_name = module.ec2.unhealthy_hosts_alarm_id
  rds_cpu_alarm_name         = module.rds.cloudwatch_alarm_cpu_id
  enable_eventbridge_rules   = true

  tags = local.common_tags
}
