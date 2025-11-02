#####################################
# Monitoring Module - Outputs
#####################################

#####################################
# SNS Topic
#####################################

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarms"
  value       = aws_sns_topic.alarms.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.alarms.name
}

#####################################
# CloudWatch Dashboard
#####################################

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = length(aws_cloudwatch_dashboard.main) > 0 ? aws_cloudwatch_dashboard.main[0].dashboard_name : null
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard"
  value       = length(aws_cloudwatch_dashboard.main) > 0 ? aws_cloudwatch_dashboard.main[0].dashboard_arn : null
}

output "dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = length(aws_cloudwatch_dashboard.main) > 0 ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main[0].dashboard_name}" : null
}

#####################################
# Log Metric Filters
#####################################

output "error_count_metric_filter_name" {
  description = "Name of the error count metric filter"
  value       = var.application_log_group_name != "" ? aws_cloudwatch_log_metric_filter.error_count[0].name : null
}

output "warning_count_metric_filter_name" {
  description = "Name of the warning count metric filter"
  value       = var.application_log_group_name != "" ? aws_cloudwatch_log_metric_filter.warning_count[0].name : null
}

#####################################
# Alarms
#####################################

output "high_error_rate_alarm_arn" {
  description = "ARN of the high error rate alarm"
  value       = var.application_log_group_name != "" && var.enable_log_alarms ? aws_cloudwatch_metric_alarm.high_error_rate[0].arn : null
}

output "critical_system_health_alarm_arn" {
  description = "ARN of the critical system health composite alarm"
  value       = var.enable_composite_alarms ? aws_cloudwatch_composite_alarm.critical_system_health[0].arn : null
}

#####################################
# CloudWatch Insights Queries
#####################################

output "error_analysis_query_id" {
  description = "ID of the error analysis Insights query"
  value       = var.application_log_group_name != "" ? aws_cloudwatch_query_definition.error_analysis[0].query_definition_id : null
}

output "slow_requests_query_id" {
  description = "ID of the slow requests Insights query"
  value       = var.application_log_group_name != "" ? aws_cloudwatch_query_definition.slow_requests[0].query_definition_id : null
}

output "request_volume_query_id" {
  description = "ID of the request volume Insights query"
  value       = var.application_log_group_name != "" ? aws_cloudwatch_query_definition.request_volume[0].query_definition_id : null
}

#####################################
# EventBridge Rules
#####################################

output "ec2_state_change_rule_arn" {
  description = "ARN of the EC2 state change EventBridge rule"
  value       = var.enable_eventbridge_rules ? aws_cloudwatch_event_rule.ec2_state_change[0].arn : null
}

output "rds_events_rule_arn" {
  description = "ARN of the RDS events EventBridge rule"
  value       = var.enable_eventbridge_rules && var.db_instance_id != "" ? aws_cloudwatch_event_rule.rds_events[0].arn : null
}
