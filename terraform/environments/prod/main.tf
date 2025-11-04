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
# ECR Module
#####################################

module "ecr" {
  source = "../../modules/ecr"

  repository_name      = "${local.name_prefix}-app"
  image_tag_mutability = "IMMUTABLE" # Production should use immutable tags
  scan_on_push         = true
  max_image_count      = 30 # Keep more images in production
  untagged_days        = 14
  allowed_principals   = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]

  common_tags = local.common_tags
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
  max_allocated_storage = 500
  storage_type          = "gp3"

  # High availability enabled
  multi_az = true

  # Backup configuration (production-grade)
  backup_retention_period  = 30
  skip_final_snapshot      = false
  delete_automated_backups = false

  # Monitoring (enhanced monitoring)
  enabled_monitoring_interval           = 60
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  # Protection enabled for production
  deletion_protection = true

  # Parameters
  max_connections = 200

  # Alarms
  create_cloudwatch_alarms = true

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
  application_port     = var.application_port
  app_version          = var.app_version
  db_secret_arn        = module.rds.db_secret_arn
  db_master_secret_arn = module.rds.master_user_secret_arn
  rds_kms_key_arn      = module.rds.kms_key_arn
  ecr_repository_url   = module.ecr.repository_url

  # Instance configuration (production-sized)
  instance_type              = "t3.small"
  root_volume_size           = 30
  enable_detailed_monitoring = true

  # Auto Scaling (production capacity)
  asg_min_size         = 2
  asg_max_size         = 6
  asg_desired_capacity = 2

  # Scaling policies
  enable_cpu_scaling      = true
  cpu_target_value        = 70
  enable_alb_scaling      = true
  alb_requests_per_target = 1000

  # Load Balancer
  enable_deletion_protection = true
  alb_idle_timeout           = 60

  # HTTPS/SSL Configuration
  certificate_arn       = var.certificate_arn
  ssl_policy            = var.ssl_policy
  enable_https_redirect = var.enable_https_redirect

  # Health checks
  health_check_path              = "/health"
  health_check_interval          = 30
  health_check_healthy_threshold = 2
  health_check_grace_period      = 300
  deregistration_delay           = 30

  # Monitoring
  create_monitoring_alarms = true
  log_retention_days       = 14

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

  # Monitoring configuration (full monitoring for production)
  enable_log_alarms        = true
  enable_composite_alarms  = true
  enable_eventbridge_rules = true

  tags = local.common_tags
}

#####################################
# WAF Module
#####################################

module "waf" {
  source = "../../modules/waf"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region
  alb_arn     = module.ec2.alb_arn

  # Rate limiting (production: stricter limits)
  rate_limit = var.waf_rate_limit

  # IP management
  ip_whitelist      = var.waf_ip_whitelist
  blocked_countries = var.waf_blocked_countries

  # Rule customization
  excluded_rules = var.waf_excluded_rules

  # Logging
  enable_logging     = true
  log_retention_days = 14

  # Monitoring
  create_cloudwatch_alarms   = true
  blocked_requests_threshold = var.waf_blocked_requests_threshold
  alarm_actions              = [module.monitoring.sns_topic_arn]

  tags = local.common_tags

  depends_on = [module.ec2]
}
