#####################################
# Development Environment
#####################################
# This configuration creates a cost-optimized development environment
# with all modules integrated
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

  # Use fewer AZs for cost optimization in dev
  azs_count = 2

  # Use single NAT Gateway for dev to save costs (~$60/month)
  single_nat_gateway = true

  # VPC Flow Logs
  enable_flow_logs         = true
  flow_logs_retention_days = 7

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
  image_tag_mutability = "MUTABLE"
  scan_on_push         = true
  max_image_count      = 10
  untagged_days        = 7
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

  # Instance configuration (cost-optimized for dev)
  instance_class    = "db.t3.micro" # Free tier eligible
  allocated_storage = 20
  storage_type      = "gp3"

  # High availability disabled for dev
  multi_az = false

  # Backup configuration (minimal for dev)
  backup_retention_period  = 1
  skip_final_snapshot      = true
  delete_automated_backups = true

  # Monitoring (basic for dev)
  enabled_monitoring_interval     = 0 # Disable enhanced monitoring
  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = []

  # Protection disabled for dev (easy cleanup)
  deletion_protection = false

  # Parameters
  max_connections = 50

  # Alarms
  create_cloudwatch_alarms = false

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
  db_secret_arn      = module.rds.db_secret_arn
  ecr_repository_url = module.ecr.repository_url

  # Instance configuration (cost-optimized)
  instance_type    = "t3.micro" # Free tier eligible
  root_volume_size = 20

  # Auto Scaling (minimal for dev)
  asg_min_size         = 1
  asg_max_size         = 2
  asg_desired_capacity = 1

  # Scaling policies
  enable_cpu_scaling = true
  cpu_target_value   = 70

  # Load Balancer
  enable_deletion_protection = false
  alb_idle_timeout           = 60

  # Health checks
  health_check_path         = "/health"
  health_check_interval     = 30
  health_check_grace_period = 300

  # Monitoring
  enable_detailed_monitoring = false
  create_monitoring_alarms   = false
  log_retention_days         = 7

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

  # Monitoring configuration
  enable_log_alarms        = false # Disable for dev to reduce noise
  enable_composite_alarms  = false
  enable_eventbridge_rules = true

  tags = local.common_tags
}
