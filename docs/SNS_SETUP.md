# SNS Email Alerts Setup Guide

This guide explains how to configure email notifications for CloudWatch alarms and AWS events.

## Overview

The infrastructure automatically creates an SNS topic and CloudWatch alarms. You only need to:
1. Add email addresses to Terraform configuration
2. Apply infrastructure changes
3. Confirm email subscriptions

Once configured, you'll receive email alerts for:
- Infrastructure issues (unhealthy hosts, database problems)
- Performance degradation (high CPU, slow response times)
- Application errors (from logs)
- AWS events (EC2 state changes, RDS events)

---

## Quick Start

### Step 1: Add Email Addresses

Edit your environment's `terraform.tfvars` file:

**Development:**
```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
```

**Production:**
```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
```

Add email addresses:
```hcl
# Monitoring configuration
alert_email_addresses = [
  "devops@example.com",
  "oncall@example.com"
]
```

### Step 2: Apply Changes

```bash
# Review changes
terraform plan

# Apply
terraform apply
```

### Step 3: Confirm Subscriptions

AWS will send confirmation emails to all addresses. Each recipient must:
1. Check inbox (and spam folder) for "AWS Notification - Subscription Confirmation"
2. Click the **"Confirm subscription"** link
3. See confirmation message in browser

⚠️ **IMPORTANT**: You won't receive alerts until you confirm the subscription!

---

## Understanding Alerts

### Alert Categories

| Category | When You'll Be Notified | Severity |
|----------|-------------------------|----------|
| **Application Health** | Unhealthy instances, HTTP 5XX errors | 🔴 Critical |
| **Performance** | High response time, slow queries | 🟠 Warning |
| **Database** | High CPU, low storage, low memory | 🔴 Critical |
| **Errors** | Application errors in logs | 🟠 Warning |
| **Infrastructure** | EC2 stopped, RDS failures | 🔴 Critical |

### Detailed Alert List

#### 1. Application Load Balancer (ALB) Alarms

**Unhealthy Hosts**
- **What**: One or more EC2 instances failed health checks
- **Threshold**: > 0 unhealthy instances for 2 minutes
- **Impact**: Reduced capacity, potential downtime
- **Action**: Check EC2 instance logs, verify application is running

**High Response Time**
- **What**: Application responding slowly
- **Threshold**: Average > 1 second for 10 minutes
- **Impact**: Poor user experience
- **Action**: Check application performance, database queries, scaling

**HTTP 5XX Errors**
- **What**: Server errors returned to users
- **Threshold**: > 10 errors in 5 minutes
- **Impact**: Users experiencing failures
- **Action**: Check application logs for errors

#### 2. RDS Database Alarms

**High CPU Utilization**
- **What**: Database CPU usage is high
- **Threshold**: > 80% for 10 minutes
- **Impact**: Slow queries, potential timeouts
- **Action**: Optimize queries, consider larger instance

**Low Storage Space**
- **What**: Running out of disk space
- **Threshold**: < 10 GB free (customizable)
- **Impact**: Database writes may fail
- **Action**: Enable storage autoscaling, archive old data

**Low Memory**
- **What**: Freeable memory is low
- **Threshold**: < 256 MB (customizable)
- **Impact**: Increased disk I/O, slower performance
- **Action**: Consider larger instance, optimize queries

**High Connections**
- **What**: Too many database connections
- **Threshold**: > 80% of max_connections
- **Impact**: New connections may fail
- **Action**: Check connection leaks, adjust max_connections

#### 3. Application Log Alarms

**High Error Rate**
- **What**: Many errors in application logs
- **Threshold**: > 10 errors in 5 minutes (customizable)
- **Impact**: Application issues affecting users
- **Action**: Check logs with CloudWatch Insights

#### 4. Composite Alarms

**Critical System Health**
- **What**: Multiple critical issues detected
- **Condition**: Unhealthy hosts OR high RDS CPU
- **Impact**: System-wide degradation
- **Action**: Immediate investigation required

#### 5. EventBridge Notifications

**EC2 Instance State Changes**
- **Events**: Instance terminated, stopped, stopping
- **Impact**: Capacity reduction, potential outage
- **Action**: Investigate why instance stopped

**RDS Events**
- **Events**: Failures, configuration changes, deletion
- **Impact**: Database issues or changes
- **Action**: Review RDS event details

---

## Email Alert Examples

### Alarm Triggered (ALARM State)

```
Subject: ALARM: "demo-app-prod-unhealthy-hosts" in EU (Stockholm)

You are receiving this email because your Amazon CloudWatch Alarm
"demo-app-prod-unhealthy-hosts" in the EU (Stockholm) region has entered
the ALARM state.

Alarm Details:
- Name:        demo-app-prod-unhealthy-hosts
- Description: Unhealthy host count is too high
- State:       ALARM -> triggered at 2024-01-15 14:32:00 UTC
- Reason:      Threshold Crossed: 1 datapoint [2.0 (15/01/24 14:31:00)]
               was greater than the threshold (0.0)
```

### Alarm Resolved (OK State)

```
Subject: OK: "demo-app-prod-unhealthy-hosts" in EU (Stockholm)

You are receiving this email because your Amazon CloudWatch Alarm
"demo-app-prod-unhealthy-hosts" in the EU (Stockholm) region has returned
to the OK state.

Alarm Details:
- Name:        demo-app-prod-unhealthy-hosts
- State:       OK -> returned to normal at 2024-01-15 14:45:00 UTC
- Reason:      Threshold Crossed: 2 datapoints [0.0 (15/01/24 14:44:00)]
               were not greater than the threshold (0.0)
```

---

## Configuration Options

### Adding Multiple Emails

```hcl
alert_email_addresses = [
  "devops@example.com",        # DevOps team
  "oncall@example.com",         # On-call rotation
  "john.doe@example.com",       # Individual
  "jane.smith@example.com"      # Individual
]
```

### Environment-Specific Configuration

**Development** - Fewer alerts, less critical:
```hcl
# Optional: may want fewer emails in dev
alert_email_addresses = [
  "dev-team@example.com"
]
```

**Production** - More recipients, critical:
```hcl
# Production should have multiple recipients
alert_email_addresses = [
  "devops@example.com",
  "oncall@example.com",
  "sre-team@example.com"
]
```

### Disabling Email Alerts

To disable email alerts, set empty list:
```hcl
alert_email_addresses = []
```

⚠️ **NOT RECOMMENDED** for production environments!

---

## Advanced Configuration

### Using AWS CLI

#### List SNS Topics
```bash
aws sns list-topics --region eu-north-1
```

#### Get Topic Details
```bash
aws sns get-topic-attributes \
  --topic-arn arn:aws:sns:eu-north-1:123456789012:demo-app-prod-alarms \
  --region eu-north-1
```

#### List Subscriptions
```bash
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:eu-north-1:123456789012:demo-app-prod-alarms \
  --region eu-north-1
```

#### Manually Add Subscription
```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:eu-north-1:123456789012:demo-app-prod-alarms \
  --protocol email \
  --notification-endpoint newuser@example.com \
  --region eu-north-1
```

### Adding SMS Notifications

While not configured by default, you can add SMS:

```bash
aws sns subscribe \
  --topic-arn <your-topic-arn> \
  --protocol sms \
  --notification-endpoint +1234567890 \
  --region eu-north-1
```

**Note**: SMS notifications have additional costs (~$0.50-0.75 per 100 messages in EU).

### Adding Slack/PagerDuty Integration

For advanced integrations:

1. **Slack**: Use AWS Chatbot
2. **PagerDuty**: Create email integration endpoint
3. **Other tools**: Use SNS HTTP/HTTPS endpoint

---

## Managing Subscriptions

### Confirming Subscriptions

If you missed the confirmation email:

```bash
# Get subscription ARN
aws sns list-subscriptions-by-topic \
  --topic-arn <topic-arn> \
  --region eu-north-1

# Request new confirmation email
aws sns get-subscription-attributes \
  --subscription-arn <subscription-arn> \
  --region eu-north-1
```

Or simply remove and re-add the email in `terraform.tfvars` and run `terraform apply`.

### Unsubscribing

**Option 1: Via Email**
- Click "Unsubscribe" link at bottom of any SNS email

**Option 2: Via Terraform**
- Remove email from `alert_email_addresses` in terraform.tfvars
- Run `terraform apply`

**Option 3: Via AWS Console**
1. Go to **SNS** → **Subscriptions**
2. Find subscription
3. Click **Delete**

### Checking Subscription Status

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn <topic-arn> \
  --region eu-north-1 \
  --query 'Subscriptions[*].[Endpoint,SubscriptionArn]' \
  --output table
```

Status meanings:
- **PendingConfirmation**: Waiting for email confirmation
- **arn:aws:sns:...**: Confirmed and active
- **Deleted**: Unsubscribed

---

## Customizing Alarms

### Adjusting Thresholds

Edit module variables in environment's `main.tf`:

**Example: RDS CPU threshold**
```hcl
module "rds" {
  source = "../../modules/rds"

  # ... other config ...

  # Adjust alarm thresholds
  alarm_cpu_threshold          = 90  # Default: 80
  alarm_free_storage_threshold = 5000000000  # 5GB in bytes
  alarm_free_memory_threshold  = 134217728   # 128MB in bytes
}
```

**Example: Application error threshold**
```hcl
module "monitoring" {
  source = "../../modules/monitoring"

  # ... other config ...

  error_rate_threshold = 20  # Default: 10 errors per 5 min
}
```

### Disabling Specific Alarms

```hcl
module "ec2" {
  source = "../../modules/ec2"

  # ... other config ...

  # Disable all EC2/ALB alarms
  create_monitoring_alarms = false
}

module "rds" {
  source = "../../modules/rds"

  # ... other config ...

  # Disable RDS alarms
  create_cloudwatch_alarms = false
}

module "monitoring" {
  source = "../../modules/monitoring"

  # ... other config ...

  # Disable specific alarm types
  enable_log_alarms        = false
  enable_composite_alarms  = false
  enable_eventbridge_rules = false
}
```

⚠️ **WARNING**: Disabling alarms reduces visibility. Only disable in non-critical environments.

---

## Troubleshooting

### Not Receiving Emails

**Problem**: Emails not arriving after `terraform apply`

**Solutions**:
1. **Check spam folder** - SNS emails often flagged as spam
2. **Verify subscription status**:
   ```bash
   aws sns list-subscriptions-by-topic \
     --topic-arn $(terraform output -raw sns_topic_arn) \
     --region eu-north-1
   ```
3. **Confirm subscription** - Look for confirmation email
4. **Check email address** - Verify no typos in terraform.tfvars
5. **Re-subscribe**:
   ```bash
   # Remove and re-add email in terraform.tfvars
   terraform apply
   ```

### Confirmation Email Not Received

**Problem**: No confirmation email after subscription

**Solutions**:
1. **Check spam folder** - Subject: "AWS Notification - Subscription Confirmation"
2. **Check email filters** - Whitelist `no-reply@sns.amazonaws.com`
3. **Re-trigger confirmation**:
   ```bash
   # Remove and re-add email
   terraform apply
   ```
4. **Try different email** - Some corporate email servers block automated emails

### Too Many Emails

**Problem**: Receiving excessive alert emails

**Solutions**:
1. **Adjust alarm thresholds** - Make them less sensitive
2. **Increase evaluation periods** - Require more consecutive breaches
3. **Fix underlying issues** - Alarms indicate real problems
4. **Use composite alarms** - Group related alarms
5. **Filter emails** - Set up email rules for different severities

### Emails After Terraform Destroy

**Problem**: Still receiving emails after destroying infrastructure

**Solution**:
```bash
# Manually unsubscribe via email link, or delete subscriptions:
aws sns list-subscriptions \
  --region eu-north-1 \
  --query 'Subscriptions[?contains(TopicArn, `demo-app`)].SubscriptionArn' \
  --output text | xargs -n1 -I {} aws sns unsubscribe --subscription-arn {} --region eu-north-1
```

---

## Testing Alerts

### Manual Alarm Trigger

```bash
# Get alarm name
aws cloudwatch describe-alarms \
  --alarm-name-prefix demo-app-prod \
  --region eu-north-1

# Manually set alarm state (for testing)
aws cloudwatch set-alarm-state \
  --alarm-name "demo-app-prod-unhealthy-hosts" \
  --state-value ALARM \
  --state-reason "Testing alert system" \
  --region eu-north-1

# Reset to OK
aws cloudwatch set-alarm-state \
  --alarm-name "demo-app-prod-unhealthy-hosts" \
  --state-value OK \
  --state-reason "Test complete" \
  --region eu-north-1
```

### Simulate Real Alert

**Test unhealthy hosts:**
```bash
# Stop application on one instance
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Environment,Values=prod" \
  --parameters 'commands=["sudo systemctl stop app"]' \
  --region eu-north-1
```

**Test high CPU:**
```bash
# Run CPU stress on instance
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Environment,Values=prod" \
  --parameters 'commands=["stress-ng --cpu 4 --timeout 300s"]' \
  --region eu-north-1
```

---

## Cost Considerations

### SNS Pricing (EU Stockholm - eu-north-1)

| Service | Cost | Details |
|---------|------|---------|
| **Email notifications** | First 1,000 free, then $2 per 100,000 | Extremely low cost |
| **HTTPS notifications** | First 1 million free, then $0.60 per million | For webhooks |
| **SMS notifications** | ~$0.50-0.75 per 100 messages | Variable by country |
| **Data transfer** | Free within AWS | Cross-region charges apply |

### Typical Monthly Costs

**Low alert volume** (5-10 alerts/day):
- ~150 emails/month
- Cost: **FREE** (under 1,000 email limit)

**Medium alert volume** (50 alerts/day):
- ~1,500 emails/month × 3 recipients = 4,500 emails
- Cost: **~$0.07/month**

**High alert volume** (200 alerts/day):
- ~6,000 emails/month × 3 recipients = 18,000 emails
- Cost: **~$0.34/month**

**Verdict**: Email alerts are essentially free. Cost is negligible compared to infrastructure.

---

## Best Practices

### 1. Email Management

✅ **DO:**
- Use distribution lists (devops@example.com) instead of individual emails
- Confirm subscriptions immediately after deployment
- Document who receives alerts and why
- Use different emails for dev vs prod

❌ **DON'T:**
- Use personal emails for production alerts
- Add too many recipients (creates alert fatigue)
- Ignore unconfirmed subscriptions

### 2. Alert Configuration

✅ **DO:**
- Test alerts after initial setup
- Adjust thresholds based on actual usage
- Keep evaluation periods at 2+ to avoid flapping
- Use composite alarms for related conditions

❌ **DON'T:**
- Set thresholds too sensitive (too many false positives)
- Disable alarms without understanding impact
- Ignore repeated alerts (they indicate real issues)

### 3. Response Process

✅ **DO:**
- Document response procedures for each alarm type
- Create runbooks for common issues
- Track alert frequency and patterns
- Review and tune alarms quarterly

❌ **DON'T:**
- Let alert fatigue set in
- Delay response to critical alarms
- Dismiss alerts without investigation

### 4. Security

✅ **DO:**
- Use corporate email addresses
- Rotate email access when team members leave
- Restrict SNS topic permissions
- Log SNS actions with CloudTrail

❌ **DON'T:**
- Expose sensitive data in alarm descriptions
- Use public/shared email accounts
- Allow public SNS topic subscriptions

---

## Integration Examples

### Slack Notification (via AWS Chatbot)

1. **Create Slack App**: https://api.slack.com/apps
2. **Configure AWS Chatbot**:
   ```bash
   # Use AWS Console: Services → AWS Chatbot → Configure new client
   # Select Slack workspace
   # Select SNS topic
   ```
3. **Test**:
   ```bash
   aws sns publish \
     --topic-arn <topic-arn> \
     --message "Test alert from AWS" \
     --region eu-north-1
   ```

### PagerDuty Integration

1. **Get PagerDuty email integration** endpoint
2. **Add to Terraform**:
   ```hcl
   alert_email_addresses = [
     "your-service@your-domain.pagerduty.com",
     "devops@example.com"
   ]
   ```

### Microsoft Teams (via Power Automate)

1. Create Power Automate flow
2. Trigger: "When an HTTP request is received"
3. Add SNS HTTPS subscription:
   ```bash
   aws sns subscribe \
     --topic-arn <topic-arn> \
     --protocol https \
     --notification-endpoint <power-automate-url> \
     --region eu-north-1
   ```

---

## Monitoring Checklist

- [ ] Email addresses added to `terraform.tfvars`
- [ ] Infrastructure deployed with `terraform apply`
- [ ] All emails confirmed subscriptions
- [ ] Test alert sent and received
- [ ] Spam filters configured to allow SNS emails
- [ ] On-call rotation documented
- [ ] Runbooks created for common alarms
- [ ] Alert response procedures documented
- [ ] Quarterly alarm review scheduled
- [ ] Backup notification method configured (Slack/PagerDuty)

---

## Summary

**Quick Setup**:
1. Add emails to `terraform.tfvars`: `alert_email_addresses = ["email@example.com"]`
2. Run `terraform apply`
3. Confirm subscriptions via email
4. Done! ✅

**What You'll Get**:
- Email notifications for all critical infrastructure issues
- Alerts for performance degradation
- Application error notifications
- AWS event notifications
- Alarm recovery notifications (when issues resolve)

**Cost**: Essentially free (~$0-0.50/month for typical usage)

---

**Need help?**
- Check CloudWatch Alarms in AWS Console
- Review SNS subscription status
- Consult main [README.md](../README.md)
- Review alarm configuration in module documentation

---

**Related Documentation**:
- [HTTPS Setup Guide](./HTTPS_SETUP.md)
- [Deployment Guide](../README.md#deployment)
- [Troubleshooting](../README.md#troubleshooting)
