#####################################
# Production Environment - Outputs
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

output "nat_gateway_count" {
  description = "Number of NAT Gateways deployed"
  value       = length(module.vpc.nat_gateway_ids)
}

#####################################
# Application Outputs
#####################################

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.ec2.alb_dns_name
}

output "alb_url" {
  description = "HTTP URL of the Application Load Balancer"
  value       = "http://${module.ec2.alb_dns_name}"
}

output "alb_https_url" {
  description = "HTTPS URL of the Application Load Balancer (if certificate configured)"
  value       = var.certificate_arn != "" ? "https://${module.ec2.alb_dns_name}" : null
}

output "application_endpoints" {
  description = "Application endpoint URLs"
  value = {
    root    = var.certificate_arn != "" ? "https://${module.ec2.alb_dns_name}/" : "http://${module.ec2.alb_dns_name}/"
    health  = var.certificate_arn != "" ? "https://${module.ec2.alb_dns_name}/health" : "http://${module.ec2.alb_dns_name}/health"
    db      = var.certificate_arn != "" ? "https://${module.ec2.alb_dns_name}/db" : "http://${module.ec2.alb_dns_name}/db"
    api     = var.certificate_arn != "" ? "https://${module.ec2.alb_dns_name}/api/items" : "http://${module.ec2.alb_dns_name}/api/items"
    metrics = var.certificate_arn != "" ? "https://${module.ec2.alb_dns_name}/metrics" : "http://${module.ec2.alb_dns_name}/metrics"
  }
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.ec2.asg_name
}

output "asg_configuration" {
  description = "Auto Scaling Group configuration"
  value = {
    min_size         = module.ec2.asg_min_size
    max_size         = module.ec2.asg_max_size
    desired_capacity = module.ec2.asg_desired_capacity
  }
}

#####################################
# Database Outputs
#####################################

output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
  sensitive   = true
}

output "db_instance_address" {
  description = "RDS instance address"
  value       = module.rds.db_instance_address
  sensitive   = true
}

output "db_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = module.rds.db_secret_arn
  sensitive   = true
}

output "db_secret_name" {
  description = "Name of the database credentials secret"
  value       = module.rds.db_secret_name
  sensitive   = true
}

output "db_multi_az" {
  description = "Whether database is Multi-AZ"
  value       = module.rds.db_instance_multi_az
}

#####################################
# Monitoring Outputs
#####################################

output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
}

output "cloudwatch_dashboard_name" {
  description = "Name of CloudWatch dashboard"
  value       = module.monitoring.dashboard_name
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  value       = module.monitoring.sns_topic_arn
}

output "sns_topic_name" {
  description = "SNS topic name for alarms"
  value       = module.monitoring.sns_topic_name
}

#####################################
# Security Outputs
#####################################

output "security_groups" {
  description = "Security group IDs"
  value = {
    alb         = module.security.alb_security_group_id
    application = module.security.application_security_group_id
    rds         = module.security.rds_security_group_id
  }
}

#####################################
# Useful Commands
#####################################

output "useful_commands" {
  description = "Useful commands for managing the infrastructure"
  sensitive   = true
  value = {
    # Application testing
    test_health = "curl ${var.certificate_arn != "" ? "https" : "http"}://${module.ec2.alb_dns_name}/health"
    test_db     = "curl ${var.certificate_arn != "" ? "https" : "http"}://${module.ec2.alb_dns_name}/db"
    get_items   = "curl ${var.certificate_arn != "" ? "https" : "http"}://${module.ec2.alb_dns_name}/api/items"
    create_item = "curl -X POST ${var.certificate_arn != "" ? "https" : "http"}://${module.ec2.alb_dns_name}/api/items -H 'Content-Type: application/json' -d '{\"name\":\"test\",\"value\":\"123\"}'"

    # Database access
    get_db_credentials = "aws secretsmanager get-secret-value --secret-id ${module.rds.db_secret_arn} --query SecretString --output text | jq ."

    # Logs
    tail_app_logs = "aws logs tail ${module.ec2.cloudwatch_log_group_name} --follow"
    query_errors  = "aws logs filter-log-events --log-group-name ${module.ec2.cloudwatch_log_group_name} --filter-pattern ERROR"

    # SSM access to instance
    list_instances      = "aws ec2 describe-instances --filters 'Name=tag:Environment,Values=prod' 'Name=instance-state-name,Values=running' --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,State.Name]' --output table"
    connect_to_instance = "aws ssm start-session --target <instance-id>"

    # Monitoring
    view_dashboard      = "open ${module.monitoring.dashboard_url}"
    list_alarms         = "aws cloudwatch describe-alarms --alarm-name-prefix ${local.name_prefix}"
    check_target_health = "aws elbv2 describe-target-health --target-group-arn ${module.ec2.target_group_arn}"

    # Scaling
    set_desired_capacity  = "aws autoscaling set-desired-capacity --auto-scaling-group-name ${module.ec2.asg_name} --desired-capacity <number>"
    view_scaling_activity = "aws autoscaling describe-scaling-activities --auto-scaling-group-name ${module.ec2.asg_name} --max-records 20"
  }
}

#####################################
# Cost Estimation
#####################################

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    ec2_t3_small             = "~$60/month (4 instances)"
    rds_db_t3_small_multi_az = "~$60/month (Multi-AZ)"
    nat_gateway_3x           = "~$100/month (3 NAT GWs)"
    alb                      = "~$20/month"
    cloudwatch               = "~$15/month"
    data_transfer            = "~$20/month"
    total_estimate           = "~$275/month"
    note                     = "Actual costs may vary based on usage. Consider Reserved Instances for 30-60% savings."
  }
}

#####################################
# Deployment Information
#####################################

output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    environment       = var.environment
    region            = var.aws_region
    high_availability = "Enabled (Multi-AZ across ${length(module.vpc.availability_zones)} AZs)"
    auto_scaling      = "Enabled (${module.ec2.asg_min_size}-${module.ec2.asg_max_size} instances)"
    database_ha       = module.rds.db_instance_multi_az ? "Enabled (Multi-AZ)" : "Disabled"
    monitoring        = "Enabled (CloudWatch Dashboard + Alarms)"
    ssl_tls           = var.certificate_arn != "" ? "Enabled (HTTPS)" : "HTTP only (configure certificate_arn for HTTPS)"

    next_steps = [
      "1. Confirm SNS email subscription (check email)",
      "2. Test application endpoints",
      "3. Review CloudWatch dashboard",
      "4. Configure Route53 DNS (if using custom domain)",
      "5. Setup backup and disaster recovery procedures",
      "6. Review and test auto-scaling policies",
      "7. Configure additional monitoring and alerts as needed"
    ]
  }
}
