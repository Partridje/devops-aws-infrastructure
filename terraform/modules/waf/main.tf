#####################################
# AWS WAF Module
#####################################
# Protects Application Load Balancer from common web attacks
# - OWASP Top 10 vulnerabilities
# - Known bad inputs
# - IP reputation lists
# - Rate limiting
#####################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module    = "waf"
      ManagedBy = "Terraform"
    }
  )
}

#####################################
# WAF Web ACL
#####################################

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.name_prefix}-web-acl"
  description = "WAF rules for ${var.name_prefix}"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: AWS Managed Rules - Core Rule Set (OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"

        # Exclude rules that might cause false positives
        dynamic "rule_action_override" {
          for_each = var.excluded_rules
          content {
            action_to_use {
              count {}
            }
            name = rule_action_override.value
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed Rules - IP Reputation List
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: Rate Limiting
  rule {
    name     = "RateLimitRule"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: Geo Blocking (optional)
  dynamic "rule" {
    for_each = length(var.blocked_countries) > 0 ? [1] : []
    content {
      name     = "GeoBlockRule"
      priority = 5

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule 6: IP Whitelist (optional)
  dynamic "rule" {
    for_each = length(var.ip_whitelist) > 0 ? [1] : []
    content {
      name     = "IPWhitelistRule"
      priority = 0 # Highest priority

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.whitelist[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-ip-whitelist"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-web-acl"
    }
  )
}

#####################################
# IP Set for Whitelist (Optional)
#####################################

resource "aws_wafv2_ip_set" "whitelist" {
  count = length(var.ip_whitelist) > 0 ? 1 : 0

  name               = "${var.name_prefix}-ip-whitelist"
  description        = "Whitelisted IP addresses"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.ip_whitelist

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-ip-whitelist"
    }
  )
}

#####################################
# WAF Association with ALB
#####################################

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

#####################################
# CloudWatch Log Group for WAF
#####################################

resource "aws_cloudwatch_log_group" "waf_logs" {
  count = var.enable_logging ? 1 : 0

  name              = "/aws/wafv2/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

#####################################
# WAF Logging Configuration
#####################################

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_logging ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.main.arn
  log_destination_configs = ["${aws_cloudwatch_log_group.waf_logs[0].arn}:*"]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

#####################################
# CloudWatch Alarms for WAF
#####################################

resource "aws_cloudwatch_metric_alarm" "blocked_requests" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-waf-blocked-requests"
  alarm_description   = "High number of requests blocked by WAF"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = var.blocked_requests_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.main.name
    Region = var.aws_region
    Rule   = "ALL"
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rate_limit_triggered" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-waf-rate-limit"
  alarm_description   = "Rate limiting triggered frequently"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.main.name
    Region = var.aws_region
    Rule   = "RateLimitRule"
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}
