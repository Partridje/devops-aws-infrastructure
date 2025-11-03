#####################################
# Monitoring Module - Simplified
#####################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "monitoring"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  )

  dashboard_name = "${var.name_prefix}-${var.environment}-dashboard"
}

#####################################
# SNS Topic for Alarms
#####################################

resource "aws_sns_topic" "alarms" {
  name         = "${var.name_prefix}-${var.environment}-alarms"
  display_name = "Alarms for ${var.name_prefix} ${var.environment}"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-alarms"
    }
  )
}

# Email subscriptions
resource "aws_sns_topic_subscription" "email_alerts" {
  count = length(var.alert_email_addresses)

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email_addresses[count.index]
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.alarms.arn
      }
    ]
  })
}

#####################################
# CloudWatch Dashboard - Simplified
#####################################

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [] # Simplified - just empty dashboard for now
  })
}
#####################################
# Log Metric Filters
#####################################

# Error count metric filter
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  count = var.application_log_group_name != "" ? 1 : 0

  name           = "${var.name_prefix}-error-count"
  log_group_name = var.application_log_group_name
  pattern        = "[time, request_id, level = ERROR*, ...]"

  metric_transformation {
    name      = "ErrorCount"
    namespace = var.custom_namespace != "" ? var.custom_namespace : "Application/${var.environment}"
    value     = "1"
    unit      = "Count"
  }
}

# Warning count metric filter
resource "aws_cloudwatch_log_metric_filter" "warning_count" {
  count = var.application_log_group_name != "" ? 1 : 0

  name           = "${var.name_prefix}-warning-count"
  log_group_name = var.application_log_group_name
  pattern        = "[time, request_id, level = WARN*, ...]"

  metric_transformation {
    name      = "WarningCount"
    namespace = var.custom_namespace != "" ? var.custom_namespace : "Application/${var.environment}"
    value     = "1"
    unit      = "Count"
  }
}

#####################################
# CloudWatch Alarms for Log Metrics
#####################################

# High error rate alarm
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  count = var.application_log_group_name != "" && var.enable_log_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-high-error-rate"
  alarm_description   = "High application error rate detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorCount"
  namespace           = var.custom_namespace != "" ? var.custom_namespace : "Application/${var.environment}"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = local.common_tags
}

#####################################
# Composite Alarms
#####################################

# Critical system health alarm
resource "aws_cloudwatch_composite_alarm" "critical_system_health" {
  count = var.enable_composite_alarms ? 1 : 0

  alarm_name        = "${var.name_prefix}-critical-system-health"
  alarm_description = "Critical system health issue detected"
  actions_enabled   = true
  alarm_actions     = [aws_sns_topic.alarms.arn]
  ok_actions        = [aws_sns_topic.alarms.arn]

  alarm_rule = "ALARM(${var.unhealthy_hosts_alarm_name}) OR ALARM(${var.rds_cpu_alarm_name})"

  tags = local.common_tags
}

#####################################
# CloudWatch Insights Queries
#####################################

resource "aws_cloudwatch_query_definition" "error_analysis" {
  count = var.application_log_group_name != "" ? 1 : 0

  name = "${var.name_prefix}-error-analysis"

  log_group_names = [var.application_log_group_name]

  query_string = <<-QUERY
    fields @timestamp, @message
    | filter @message like /ERROR/
    | stats count() by bin(5m)
  QUERY
}

resource "aws_cloudwatch_query_definition" "slow_requests" {
  count = var.application_log_group_name != "" ? 1 : 0

  name = "${var.name_prefix}-slow-requests"

  log_group_names = [var.application_log_group_name]

  query_string = <<-QUERY
    fields @timestamp, @message, duration
    | filter duration > 1000
    | sort duration desc
    | limit 20
  QUERY
}

resource "aws_cloudwatch_query_definition" "request_volume" {
  count = var.application_log_group_name != "" ? 1 : 0

  name = "${var.name_prefix}-request-volume"

  log_group_names = [var.application_log_group_name]

  query_string = <<-QUERY
    fields @timestamp
    | stats count() as request_count by bin(1m)
    | sort @timestamp desc
  QUERY
}

#####################################
# EventBridge Rules (Optional)
#####################################

# Rule for EC2 state changes
resource "aws_cloudwatch_event_rule" "ec2_state_change" {
  count = var.enable_eventbridge_rules ? 1 : 0

  name        = "${var.name_prefix}-ec2-state-change"
  description = "Capture EC2 instance state changes"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["terminated", "stopped", "stopping"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "ec2_state_change_sns" {
  count = var.enable_eventbridge_rules ? 1 : 0

  rule      = aws_cloudwatch_event_rule.ec2_state_change[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alarms.arn
}

# Rule for RDS events
resource "aws_cloudwatch_event_rule" "rds_events" {
  count = var.enable_eventbridge_rules ? 1 : 0

  name        = "${var.name_prefix}-rds-events"
  description = "Capture RDS important events"

  event_pattern = jsonencode({
    source      = ["aws.rds"]
    detail-type = ["RDS DB Instance Event"]
    detail = {
      EventCategories = ["failure", "configuration change", "deletion"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "rds_events_sns" {
  count = var.enable_eventbridge_rules ? 1 : 0

  rule      = aws_cloudwatch_event_rule.rds_events[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.alarms.arn
}
