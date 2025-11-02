#####################################
# EC2 Module - Outputs
#####################################

#####################################
# Load Balancer
#####################################

output "alb_id" {
  description = "ID of the Application Load Balancer"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB (for CloudWatch metrics)"
  value       = aws_lb.main.arn_suffix
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB (for Route53)"
  value       = aws_lb.main.zone_id
}

output "alb_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_https_url" {
  description = "HTTPS URL of the Application Load Balancer (if HTTPS enabled)"
  value       = var.certificate_arn != "" ? "https://${aws_lb.main.dns_name}" : null
}

#####################################
# Target Group
#####################################

output "target_group_id" {
  description = "ID of the target group"
  value       = aws_lb_target_group.main.id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.main.arn
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group (for CloudWatch metrics)"
  value       = aws_lb_target_group.main.arn_suffix
}

output "target_group_name" {
  description = "Name of the target group"
  value       = aws_lb_target_group.main.name
}

#####################################
# Auto Scaling Group
#####################################

output "asg_id" {
  description = "ID of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.id
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.arn
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.name
}

output "asg_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.min_size
}

output "asg_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.max_size
}

output "asg_desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.desired_capacity
}

#####################################
# Launch Template
#####################################

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.main.id
}

output "launch_template_arn" {
  description = "ARN of the launch template"
  value       = aws_launch_template.main.arn
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.main.latest_version
}

output "launch_template_default_version" {
  description = "Default version of the launch template"
  value       = aws_launch_template.main.default_version
}

#####################################
# IAM
#####################################

output "iam_role_name" {
  description = "Name of the IAM role for EC2 instances"
  value       = aws_iam_role.ec2_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for EC2 instances"
  value       = aws_iam_role.ec2_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.arn
}

#####################################
# CloudWatch
#####################################

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.application.arn
}

#####################################
# Scaling Policies
#####################################

output "cpu_scaling_policy_arn" {
  description = "ARN of the CPU-based scaling policy (if enabled)"
  value       = var.enable_cpu_scaling ? aws_autoscaling_policy.cpu_target_tracking[0].arn : null
}

output "alb_scaling_policy_arn" {
  description = "ARN of the ALB-based scaling policy (if enabled)"
  value       = var.enable_alb_scaling ? aws_autoscaling_policy.alb_target_tracking[0].arn : null
}

#####################################
# Listeners
#####################################

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (if enabled)"
  value       = var.certificate_arn != "" ? aws_lb_listener.https[0].arn : null
}

#####################################
# Alarms
#####################################

output "unhealthy_hosts_alarm_id" {
  description = "ID of the unhealthy hosts alarm (if created)"
  value       = var.create_monitoring_alarms ? aws_cloudwatch_metric_alarm.unhealthy_hosts[0].id : null
}

output "high_response_time_alarm_id" {
  description = "ID of the high response time alarm (if created)"
  value       = var.create_monitoring_alarms ? aws_cloudwatch_metric_alarm.high_response_time[0].id : null
}

output "http_5xx_errors_alarm_id" {
  description = "ID of the HTTP 5xx errors alarm (if created)"
  value       = var.create_monitoring_alarms ? aws_cloudwatch_metric_alarm.http_5xx_errors[0].id : null
}

#####################################
# AMI
#####################################

output "ami_id" {
  description = "ID of the AMI used for instances"
  value       = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
}

output "ami_name" {
  description = "Name of the AMI used for instances"
  value       = var.ami_id != "" ? "Custom AMI" : data.aws_ami.amazon_linux_2023.name
}
