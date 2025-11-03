#####################################
# WAF Module - Outputs
#####################################

output "web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.id
}

output "web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_name" {
  description = "Name of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.name
}

output "web_acl_capacity" {
  description = "Web ACL capacity units used"
  value       = aws_wafv2_web_acl.main.capacity
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for WAF logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.waf_logs[0].name : null
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group for WAF logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.waf_logs[0].arn : null
}

output "ip_whitelist_arn" {
  description = "ARN of the IP whitelist set (if created)"
  value       = length(var.ip_whitelist) > 0 ? aws_wafv2_ip_set.whitelist[0].arn : null
}
