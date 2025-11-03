#####################################
# Development Environment - Outputs
#####################################

#####################################
# VPC Outputs
#####################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "availability_zones" {
  description = "Availability zones used"
  value       = module.vpc.availability_zones
}

#####################################
# ECR Outputs
#####################################

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = module.ecr.repository_name
}

#####################################
# Application Outputs
#####################################

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.ec2.alb_dns_name
}

output "alb_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${module.ec2.alb_dns_name}"
}

output "application_endpoints" {
  description = "Application endpoint URLs"
  value = {
    root    = "http://${module.ec2.alb_dns_name}/"
    health  = "http://${module.ec2.alb_dns_name}/health"
    db      = "http://${module.ec2.alb_dns_name}/db"
    api     = "http://${module.ec2.alb_dns_name}/api/items"
    metrics = "http://${module.ec2.alb_dns_name}/metrics"
  }
}

#####################################
# Database Outputs
#####################################

output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "db_instance_address" {
  description = "RDS instance address"
  value       = module.rds.db_instance_address
}

output "db_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = module.rds.db_secret_arn
}

output "db_secret_name" {
  description = "Name of the database credentials secret"
  value       = module.rds.db_secret_name
}

#####################################
# Monitoring Outputs
#####################################

output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  value       = module.monitoring.sns_topic_arn
}

#####################################
# Useful Commands
#####################################

output "useful_commands" {
  description = "Useful commands for managing the infrastructure"
  value = {
    # ECR login and push
    ecr_login   = "aws ecr get-login-password --region ${data.aws_region.current.id} | docker login --username AWS --password-stdin ${module.ecr.repository_url}"
    docker_tag  = "docker tag demo-flask-app:latest ${module.ecr.repository_url}:latest"
    docker_push = "docker push ${module.ecr.repository_url}:latest"

    # Application testing
    test_health = "curl http://${module.ec2.alb_dns_name}/health"
    test_db     = "curl http://${module.ec2.alb_dns_name}/db"
    get_items   = "curl http://${module.ec2.alb_dns_name}/api/items"
    create_item = "curl -X POST http://${module.ec2.alb_dns_name}/api/items -H 'Content-Type: application/json' -d '{\"name\":\"test\",\"value\":\"123\"}'"

    # Database access
    get_db_credentials = "aws secretsmanager get-secret-value --secret-id ${module.rds.db_secret_arn} --query SecretString --output text | jq ."

    # Logs
    tail_app_logs = "aws logs tail ${module.ec2.cloudwatch_log_group_name} --follow"

    # SSM access to instance
    list_instances      = "aws ec2 describe-instances --filters 'Name=tag:Environment,Values=dev' 'Name=instance-state-name,Values=running' --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,State.Name]' --output table"
    connect_to_instance = "aws ssm start-session --target <instance-id>"

    # Monitoring
    view_dashboard = "open ${module.monitoring.dashboard_url}"
  }
}

#####################################
# Cost Estimation
#####################################

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    ec2_t3_micro    = "~$7/month (1 instance)"
    rds_db_t3_micro = "~$15/month (single-AZ)"
    nat_gateway     = "~$32/month (1 NAT GW)"
    alb             = "~$20/month"
    cloudwatch      = "~$5/month"
    data_transfer   = "~$5/month"
    total_estimate  = "~$84/month"
    note            = "Actual costs may vary based on usage"
  }
}
