# Monitoring Module

Comprehensive CloudWatch monitoring solution with dashboards, alarms, log metric filters, and SNS notifications. Provides centralized observability for your entire infrastructure.

## Features

- ✅ **CloudWatch Dashboard**: Visual metrics for ALB, ASG, EC2, RDS
- ✅ **SNS Alerts**: Email notifications for alarms
- ✅ **Log Metric Filters**: Track errors and warnings from logs
- ✅ **CloudWatch Insights**: Pre-configured queries for troubleshooting
- ✅ **Composite Alarms**: System-wide health monitoring
- ✅ **EventBridge Rules**: Automated responses to state changes
- ✅ **Cost-Optimized**: Minimal overhead, pay-per-use

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              CloudWatch Dashboard                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐│
│  │   ALB    │  │   ASG    │  │   EC2    │  │   RDS   ││
│  │ Metrics  │  │ Metrics  │  │ Metrics  │  │ Metrics ││
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘│
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  CloudWatch Alarms   │
              │  - High CPU          │
              │  - Unhealthy Hosts   │
              │  - High Error Rate   │
              └──────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │     SNS Topic        │
              │  (Email Alerts)      │
              └──────────────────────┘
                         │
                         ▼
              📧 team@company.com
```

## Usage

### Basic Example

```hcl
module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix = "myapp-dev"
  environment = "dev"
  aws_region  = "eu-north-1"

  # SNS alerts
  alert_email_addresses = ["devops@company.com"]

  # Resource identifiers
  alb_arn_suffix           = module.ec2.alb_arn_suffix
  target_group_arn_suffix  = module.ec2.target_group_arn_suffix
  asg_name                 = module.ec2.asg_name
  db_instance_id           = module.rds.db_instance_id
  application_log_group_name = module.ec2.cloudwatch_log_group_name

  tags = {
    Project = "MyApp"
    Team    = "DevOps"
  }
}
```

### Production Example

```hcl
module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix = "myapp-prod"
  environment = "prod"
  aws_region  = "eu-north-1"

  # Multiple alert recipients
  alert_email_addresses = [
    "devops@company.com",
    "oncall@company.com",
    "sre-team@company.com"
  ]

  # Resource identifiers
  alb_arn                    = module.ec2.alb_arn
  alb_arn_suffix             = module.ec2.alb_arn_suffix
  target_group_arn_suffix    = module.ec2.target_group_arn_suffix
  asg_name                   = module.ec2.asg_name
  db_instance_id             = module.rds.db_instance_id
  application_log_group_name = module.ec2.cloudwatch_log_group_name

  # Custom metrics namespace
  custom_namespace = "Production/MyApp"

  # Log-based alarms
  enable_log_alarms     = true
  error_rate_threshold  = 5  # More sensitive in prod

  # Composite alarms for system health
  enable_composite_alarms    = true
  unhealthy_hosts_alarm_name = "${module.ec2.unhealthy_hosts_alarm_id}"
  rds_cpu_alarm_name         = "${module.rds.cloudwatch_alarm_cpu_id}"

  # EventBridge for automation
  enable_eventbridge_rules = true

  tags = {
    Project     = "MyApp"
    Environment = "Production"
    CostCenter  = "Engineering"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix for resource names | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| aws_region | AWS region | `string` | n/a | yes |
| alert_email_addresses | Email addresses for alerts | `list(string)` | `[]` | no |
| alb_arn_suffix | ALB ARN suffix | `string` | `""` | no |
| target_group_arn_suffix | Target group ARN suffix | `string` | `""` | no |
| asg_name | Auto Scaling Group name | `string` | `""` | no |
| db_instance_id | RDS instance ID | `string` | `""` | no |
| application_log_group_name | Application log group name | `string` | `""` | no |
| custom_namespace | Custom CloudWatch namespace | `string` | `""` | no |
| enable_log_alarms | Enable log-based alarms | `bool` | `true` | no |
| error_rate_threshold | Error count threshold | `number` | `10` | no |
| enable_composite_alarms | Enable composite alarms | `bool` | `false` | no |
| enable_eventbridge_rules | Enable EventBridge rules | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| sns_topic_arn | SNS topic ARN for alarms |
| dashboard_name | CloudWatch dashboard name |
| dashboard_url | URL to CloudWatch dashboard |

## Dashboard Widgets

The dashboard includes:

### ALB Metrics
- **Request Count & Status Codes**: Total requests, 2xx, 4xx, 5xx responses
- **Response Time**: Average and p99 latency
- **Target Health**: Healthy vs unhealthy target count

### Auto Scaling Metrics
- **Capacity**: Desired, in-service, min, max instances
- **CPU Utilization**: Average and maximum CPU across instances

### RDS Metrics
- **CPU & Connections**: Database CPU usage and active connections
- **Storage & Memory**: Free storage space and freeable memory
- **I/O Latency**: Read and write latency

### Application Logs
- **Recent Errors**: Last 20 error messages from application logs

## Log Metric Filters

Automatically tracks:

### Error Count
- Pattern: `[time, request_id, level = ERROR*, ...]`
- Metric: `ErrorCount` in custom namespace
- Alarm: Triggers when > threshold in 5 minutes

### Warning Count
- Pattern: `[time, request_id, level = WARN*, ...]`
- Metric: `WarningCount` in custom namespace

## CloudWatch Insights Queries

Pre-configured queries for common troubleshooting:

### Error Analysis
```sql
fields @timestamp, @message
| filter @message like /ERROR/
| stats count() by bin(5m)
```

### Slow Requests
```sql
fields @timestamp, @message, duration
| filter duration > 1000
| sort duration desc
| limit 20
```

### Request Volume
```sql
fields @timestamp
| stats count() as request_count by bin(1m)
| sort @timestamp desc
```

## Accessing the Dashboard

### AWS Console
```bash
# Open dashboard URL from Terraform output
terraform output -raw dashboard_url | xargs open
```

### AWS CLI
```bash
# Get dashboard JSON
aws cloudwatch get-dashboard \
  --dashboard-name $(terraform output -raw dashboard_name)
```

## Setting Up Email Alerts

### Confirm SNS Subscription
After deployment, recipients will receive confirmation emails:
1. Check email inbox for "AWS Notification - Subscription Confirmation"
2. Click confirmation link
3. Subscription is now active

### Test Alerts
```bash
# Publish test message
aws sns publish \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --subject "Test Alert" \
  --message "This is a test notification from CloudWatch"
```

## EventBridge Rules

Automatically captures and alerts on:

### EC2 State Changes
- **Events**: Instance terminated, stopped, stopping
- **Action**: Sends notification to SNS topic
- **Use Case**: Track unexpected instance terminations

### RDS Events
- **Events**: Database failures, configuration changes, deletions
- **Action**: Sends notification to SNS topic
- **Use Case**: Immediate awareness of database issues

## Cost Considerations

### Estimated Monthly Costs

| Component | Cost | Notes |
|-----------|------|-------|
| Dashboard | Free | No charge for dashboards |
| Standard Alarms | $0.10/alarm | First 10 free |
| Composite Alarms | $0.50/alarm | |
| Log Ingestion | $0.50/GB | For application logs |
| Log Storage | $0.03/GB/month | |
| SNS | $0.50/million | First 1,000 free |
| EventBridge | Free | For these rules |

**Typical cost for dev**: ~$2-5/month
**Typical cost for prod**: ~$10-20/month

### Cost Optimization Tips

1. **Adjust log retention**:
   ```hcl
   log_retention_days = 7  # Instead of 30
   ```

2. **Filter logs before ingestion**:
   ```bash
   # Only send ERROR and WARN logs to CloudWatch
   ```

3. **Use metric filters sparingly**:
   - Each metric filter incurs log processing costs

4. **Disable alarms in dev**:
   ```hcl
   enable_log_alarms = false  # For dev environments
   ```

## Integration with PagerDuty

Add PagerDuty integration endpoint to SNS:

```hcl
resource "aws_sns_topic_subscription" "pagerduty" {
  topic_arn = module.monitoring.sns_topic_arn
  protocol  = "https"
  endpoint  = "https://events.pagerduty.com/integration/YOUR_KEY/enqueue"
}
```

## Integration with Slack

Use AWS Chatbot for Slack notifications:

```hcl
resource "aws_chatbot_slack_channel_configuration" "alerts" {
  configuration_name = "myapp-alerts"
  slack_channel_id   = "C01234567"
  slack_team_id      = "T01234567"

  sns_topic_arns = [module.monitoring.sns_topic_arn]

  iam_role_arn = aws_iam_role.chatbot.arn
}
```

## Troubleshooting

### Issue: Not receiving email alerts

**Check 1**: Verify SNS subscription
```bash
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_topic_arn)
```

**Check 2**: Check spam folder
- AWS confirmation emails sometimes go to spam

**Check 3**: Test SNS topic
```bash
aws sns publish \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --message "Test"
```

### Issue: Dashboard shows no data

**Check 1**: Verify resource ARNs are correct
```bash
terraform output
```

**Check 2**: Wait for metrics
- CloudWatch metrics can take 5-15 minutes to appear

**Check 3**: Check metric namespace
```bash
aws cloudwatch list-metrics --namespace AWS/ApplicationELB
```

### Issue: Log metric filters not working

**Check 1**: Verify log pattern matches your logs
```bash
aws logs filter-log-events \
  --log-group-name /aws/ec2/myapp-application \
  --filter-pattern '[time, request_id, level = ERROR*, ...]'
```

**Check 2**: Test pattern
- Generate test logs
- Check CloudWatch Insights with same pattern

## Examples

Complete examples in `examples/` directory:
- `examples/basic-monitoring/` - Minimal monitoring setup
- `examples/production-monitoring/` - Full production monitoring

## Authors

Created and maintained by DevOps Team

## License

MIT Licensed. See LICENSE for full details.
