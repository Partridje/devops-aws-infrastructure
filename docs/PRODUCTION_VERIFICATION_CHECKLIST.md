# Production Verification Checklist

Sequential list of checks for verifying production infrastructure.

## Preparation

```bash
# Set environment variables
export AWS_REGION=eu-north-1
export ENV=prod
export ALB_URL="$(terraform output -raw alb_url)"

# Get ASG name
export ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `prod`)].AutoScalingGroupName' \
  --output text)

# Get DB instance ID
export DB_INSTANCE=$(aws rds describe-db-instances \
  --region $AWS_REGION \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `prod`)].DBInstanceIdentifier' \
  --output text)

echo "ASG_NAME: $ASG_NAME"
echo "DB_INSTANCE: $DB_INSTANCE"
```

---

## 1. Basic Infrastructure Checks

### 1.1 VPC and Networking Check

```bash
# ✓ VPC exists
aws ec2 describe-vpcs \
  --region $AWS_REGION \
  --filters "Name=tag:Project,Values=demo-app" "Name=tag:Environment,Values=prod" \
  --query 'Vpcs[].[VpcId,CidrBlock,State]' \
  --output table

# ✓ 3 Availability Zones
aws ec2 describe-subnets \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" \
  --query 'Subnets[?contains(Tags[?Key==`Name`].Value, `public`)].AvailabilityZone' \
  --output text | wc -w

# ✓ NAT Gateways are working
aws ec2 describe-nat-gateways \
  --region $AWS_REGION \
  --filter "Name=tag:Environment,Values=prod" \
  --query 'NatGateways[].[NatGatewayId,State,SubnetId]' \
  --output table
```

**Expected result:**
- 1 VPC in `available` state
- 3 Availability Zones
- 3 NAT Gateways in `available` state

---

### 1.2 EC2 Instances Check

```bash
# ✓ Instances are running
aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Placement.AvailabilityZone,PrivateIpAddress]' \
  --output table

# ✓ Instance count matches desired capacity
INSTANCE_COUNT=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text | wc -w)

echo "Running instances: $INSTANCE_COUNT (expected: 2)"
```

**Expected result:**
- 2 instances of type `t3.small`
- State `running`
- Distributed across different AZs

---

### 1.3 Auto Scaling Group Check

```bash
# ✓ ASG configuration
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize,HealthCheckType,HealthCheckGracePeriod]' \
  --output table

# ✓ Scaling policies
aws autoscaling describe-policies \
  --auto-scaling-group-name $ASG_NAME \
  --region $AWS_REGION \
  --query 'ScalingPolicies[].[PolicyName,PolicyType,Enabled]' \
  --output table
```

**Expected result:**
- MinSize: 2, DesiredCapacity: 2, MaxSize: 6
- HealthCheckType: `ELB`
- 2 scaling policies (CPU and ALB)

---

### 1.4 RDS Check

```bash
# ✓ RDS status
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].[DBInstanceStatus,MultiAZ,DBInstanceClass,AllocatedStorage,BackupRetentionPeriod,DeletionProtection]' \
  --output table

# ✓ Automated backups
aws rds describe-db-snapshots \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --snapshot-type automated \
  --query 'DBSnapshots[].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table | head -10
```

**Expected result:**
- Status: `available`
- MultiAZ: `True`
- Instance class: `db.t3.small`
- Backup retention: 30 days
- DeletionProtection: `True`
- Automated snapshots exist

---

## 2. Application Check

### 2.1 Health Check

```bash
# ✓ Health endpoint responds
curl -s http://$ALB_URL/health | jq .

# ✓ Application version
VERSION=$(curl -s http://$ALB_URL/health | jq -r '.version')
echo "Application version: $VERSION (expected: 1.0.0)"

# ✓ Database status
DB_STATUS=$(curl -s http://$ALB_URL/health | jq -r '.checks.database')
echo "Database status: $DB_STATUS (expected: ok or not_initialized)"
```

**Expected result:**
- HTTP 200
- Status: `healthy`
- Version: `1.0.0`
- Database: connected

---

### 2.2 Application Endpoints

```bash
# ✓ Root endpoint
echo "Testing root endpoint..."
curl -s http://$ALB_URL/ | jq .

# ✓ Database endpoint
echo "Testing database endpoint..."
curl -s http://$ALB_URL/db | jq .

# ✓ API endpoint
echo "Testing API endpoint..."
curl -s http://$ALB_URL/api/items | jq .

# ✓ Create record
echo "Creating test item..."
curl -X POST http://$ALB_URL/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"test-item","value":123}' | jq .

# ✓ Verify record was created
curl -s http://$ALB_URL/api/items | jq .
```

**Expected result:**
- All endpoints return HTTP 200
- Database connection works
- CRUD operations work

---

### 2.3 Load Balancer Health

```bash
# ✓ Target Group health
TG_ARN=$(aws elbv2 describe-target-groups \
  --region $AWS_REGION \
  --query "TargetGroups[?contains(TargetGroupName, 'demo-a')].TargetGroupArn" \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $AWS_REGION \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table

# ✓ Unhealthy targets
UNHEALTHY=$(aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $AWS_REGION \
  --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`]' \
  --output json)

if [ "$UNHEALTHY" == "[]" ]; then
  echo "✓ All targets are healthy"
else
  echo "✗ Some targets are unhealthy:"
  echo $UNHEALTHY | jq .
fi
```

**Expected result:**
- All targets in `healthy` state
- No unhealthy targets

---

## 3. Monitoring and Alerts

### 3.1 SNS Email Subscription

```bash
# ✓ Subscription created
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:$AWS_REGION:851725636341:demo-app-prod-prod-alarms \
  --region $AWS_REGION \
  --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' \
  --output table

# Check status
SUBSCRIPTION_STATUS=$(aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:$AWS_REGION:851725636341:demo-app-prod-prod-alarms \
  --region $AWS_REGION \
  --query 'Subscriptions[0].SubscriptionArn' \
  --output text)

if [[ "$SUBSCRIPTION_STATUS" == *"PendingConfirmation"* ]]; then
  echo "⚠️  Email subscription pending confirmation"
  echo "Check email: your-email@example.com"
else
  echo "✓ Email subscription confirmed"
fi
```

**Action:** If PendingConfirmation - confirm email!

---

### 3.2 CloudWatch Alarms

```bash
# ✓ List of alarms
aws cloudwatch describe-alarms \
  --region $AWS_REGION \
  --alarm-name-prefix demo-app-prod \
  --query 'MetricAlarms[].[AlarmName,StateValue,ActionsEnabled]' \
  --output table

# ✓ Alarms in OK state
ALARM_COUNT=$(aws cloudwatch describe-alarms \
  --region $AWS_REGION \
  --alarm-name-prefix demo-app-prod \
  --state-value ALARM \
  --query 'MetricAlarms[].AlarmName' \
  --output text | wc -w)

if [ "$ALARM_COUNT" -eq 0 ]; then
  echo "✓ No alarms in ALARM state"
else
  echo "⚠️  $ALARM_COUNT alarms in ALARM state:"
  aws cloudwatch describe-alarms \
    --region $AWS_REGION \
    --alarm-name-prefix demo-app-prod \
    --state-value ALARM \
    --query 'MetricAlarms[].[AlarmName,StateReason]' \
    --output table
fi
```

**Expected result:**
- 10+ alarms created
- All in `OK` state
- ActionsEnabled: `true`

---

### 3.3 CloudWatch Logs

```bash
# ✓ Log groups exist
aws logs describe-log-groups \
  --region $AWS_REGION \
  --log-group-name-prefix "/aws" \
  --query 'logGroups[?contains(logGroupName, `demo-app-prod`)].logGroupName' \
  --output table

# ✓ Logs are being written
echo "Recent application logs:"
aws logs tail /aws/ec2/demo-app-prod-application \
  --region $AWS_REGION \
  --since 5m \
  --format short | tail -20

# ✓ Check for ERRORs
ERROR_COUNT=$(aws logs filter-log-events \
  --region $AWS_REGION \
  --log-group-name /aws/ec2/demo-app-prod-application \
  --filter-pattern "ERROR" \
  --start-time $(($(date +%s) - 3600))000 \
  --query 'events[].message' \
  --output text | wc -l)

echo "Errors in last hour: $ERROR_COUNT"
```

**Expected result:**
- 3 log groups: application, RDS, VPC flow logs
- Logs are being written in real-time
- Minimal ERROR logs

---

### 3.4 CloudWatch Dashboard

```bash
# ✓ Dashboard exists
aws cloudwatch list-dashboards \
  --region $AWS_REGION \
  --query 'DashboardEntries[?contains(DashboardName, `prod`)].[DashboardName]' \
  --output table

# Get URL
DASHBOARD_URL="https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards/dashboard/demo-app-prod-prod-dashboard"
echo "Dashboard URL: $DASHBOARD_URL"
```

---

## 4. Security

### 4.1 WAF Protection

```bash
# ✓ WAF Web ACL created
aws wafv2 list-web-acls \
  --region $AWS_REGION \
  --scope REGIONAL \
  --query 'WebACLs[?contains(Name, `prod`)].[Name,Id]' \
  --output table

# ✓ WAF rules
WAF_ID=$(aws wafv2 list-web-acls \
  --region $AWS_REGION \
  --scope REGIONAL \
  --query 'WebACLs[?contains(Name, `prod`)].Id' \
  --output text)

aws wafv2 get-web-acl \
  --region $AWS_REGION \
  --scope REGIONAL \
  --id $WAF_ID \
  --query 'WebACL.Rules[].[Name,Priority]' \
  --output table

# ✓ WAF metrics
aws cloudwatch get-metric-statistics \
  --region $AWS_REGION \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --dimensions Name=WebACL,Value=demo-app-prod-web-acl Name=Region,Value=$AWS_REGION Name=Rule,Value=ALL \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --query 'Datapoints[0].Sum'
```

**Expected result:**
- WAF is active
- 5-6 rules configured
- BlockedRequests metric is available

---

### 4.2 Security Groups

```bash
# ✓ Security groups
aws ec2 describe-security-groups \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" \
  --query 'SecurityGroups[].[GroupName,GroupId]' \
  --output table

# ✓ ALB security group (80, 443)
ALB_SG=$(aws ec2 describe-security-groups \
  --region $AWS_REGION \
  --filters "Name=tag:Name,Values=*alb*" "Name=tag:Environment,Values=prod" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

aws ec2 describe-security-groups \
  --region $AWS_REGION \
  --group-ids $ALB_SG \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,ToPort,IpRanges[0].CidrIp]' \
  --output table
```

**Expected result:**
- 3 security groups: ALB, Application, RDS
- ALB: port 80 open (443 if certificate exists)
- Application: access only from ALB
- RDS: access only from Application SG

---

### 4.3 Secrets Manager

```bash
# ✓ Secrets exist
aws secretsmanager list-secrets \
  --region $AWS_REGION \
  --query 'SecretList[?contains(Name, `prod`)].[Name,ARN]' \
  --output table

# ✓ Rotation enabled (if configured)
aws secretsmanager describe-secret \
  --secret-id demo-app-prod-db-creds \
  --region $AWS_REGION \
  --query '[RotationEnabled,RotationRules]' \
  --output table
```

---

## 5. Functional Testing

### 5.1 Rate Limiting Test (WAF)

```bash
echo "Testing WAF rate limiting (sending 100 rapid requests)..."

# Send many requests quickly
for i in {1..100}; do
  curl -s -o /dev/null -w "%{http_code}\n" http://$ALB_URL/ &
done
wait

sleep 2

# Check that WAF is blocking
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_URL/)
if [ "$HTTP_CODE" == "403" ]; then
  echo "✓ WAF rate limiting works (got 403)"
else
  echo "⚠️  Got $HTTP_CODE (expected 403 after rate limit)"
fi

# Wait 5 minutes for block to be lifted
echo "Waiting 5 minutes for rate limit to reset..."
```

**Expected result:** After ~2000 requests we get 403

---

### 5.2 Multi-AZ Distribution Test

```bash
# ✓ Instances in different AZs
echo "Checking instance distribution across AZs..."

aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone]' \
  --output table

# Make requests and see which AZs respond
echo "Making 20 requests to check AZ distribution..."
for i in {1..20}; do
  curl -s http://$ALB_URL/health | jq -r '.instance.az'
done | sort | uniq -c
```

**Expected result:** Requests are distributed across different AZs

---

### 5.3 Database Connection Pool Test

```bash
# ✓ Connection pool works
for i in {1..10}; do
  echo "Request $i:"
  curl -s http://$ALB_URL/db | jq '.pool_size'
done

# All should show pool_size: 10
```

---

### 5.4 Performance Test

```bash
# ✓ Response time
echo "Measuring response times (10 requests)..."

for i in {1..10}; do
  curl -o /dev/null -s -w "Response time: %{time_total}s\n" http://$ALB_URL/health
done

# ✓ CloudWatch ALB latency
aws cloudwatch get-metric-statistics \
  --region $AWS_REGION \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=app/demo-app-prod-alb/* \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  --query 'Datapoints[].[Timestamp,Average,Maximum]' \
  --output table
```

**Expected result:** Response time < 200ms

---

## 6. Auto Scaling Test

### 6.1 Manual Scaling Test

```bash
echo "Current ASG configuration:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' \
  --output table

# Scale up to 4
echo "Scaling up to 4 instances..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 4 \
  --region $AWS_REGION

echo "Waiting for instances to launch..."
sleep 60

# Check
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,HealthStatus,LifecycleState]' \
  --output table

# Scale back down
echo "Scaling back to 2 instances..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 2 \
  --region $AWS_REGION
```

**Expected result:** ASG scales up to 4, then back down to 2

---

### 6.2 CPU-Based Scaling (Optional, creates load!)

```bash
echo "⚠️  This will create high CPU load!"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Skipped"
  exit 0
fi

# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo "Connecting to $INSTANCE_ID via SSM..."
echo "Run on instance: stress --cpu 4 --timeout 300s"
echo ""
echo "Then monitor scaling in another terminal:"
echo "watch -n 10 'aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region $AWS_REGION --query \"AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]\" --output text'"

# Open SSM session
aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION
```

---

## 7. Test Email Notifications

### 7.1 Send test notification

```bash
# After confirming email subscription
echo "Sending test notification..."
aws sns publish \
  --topic-arn arn:aws:sns:$AWS_REGION:851725636341:demo-app-prod-prod-alarms \
  --subject "Test Alert from Production" \
  --message "This is a test notification from production infrastructure. If you receive this, email alerts are working correctly!" \
  --region $AWS_REGION

echo "✓ Test notification sent. Check email: your-email@example.com"
```

**Expected result:** Email arrives within 1 minute

---

## 8. Disaster Recovery Test (CAUTION!)

### 8.1 Terminate Instance (failure simulation)

```bash
echo "⚠️  This will terminate 1 instance to simulate failure!"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Skipped"
  exit 0
fi

# Terminate 1 instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo "Terminating $INSTANCE_ID..."
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $AWS_REGION

# Check that application is available
echo "Checking application availability..."
for i in {1..10}; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_URL/health)
  echo "Request $i: HTTP $HTTP_CODE"
  sleep 2
done

# ASG should launch a new instance
echo "Waiting for ASG to launch replacement..."
sleep 60

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,HealthStatus,LifecycleState]' \
  --output table
```

**Expected result:**
- Application remains available (zero downtime)
- ASG automatically launches replacement
- After 2-3 minutes capacity is restored

---

## Summary Checklist

Mark completed checks:

**Infrastructure:**
- [ ] VPC and Networking (3 AZ, NAT Gateways)
- [ ] EC2 Instances (2 running, t3.small)
- [ ] Auto Scaling Group (min=2, max=6, policies enabled)
- [ ] RDS (Multi-AZ, backups enabled)

**Application:**
- [ ] Health check works
- [ ] All endpoints respond (/, /health, /db, /api/items)
- [ ] Database connection works
- [ ] CRUD operations work
- [ ] Load Balancer targets healthy

**Monitoring:**
- [ ] SNS email subscription confirmed
- [ ] CloudWatch alarms in OK state
- [ ] CloudWatch Logs are being written
- [ ] Dashboard is accessible
- [ ] Test email notification received

**Security:**
- [ ] WAF is active and working
- [ ] Rate limiting triggers
- [ ] Security groups configured correctly
- [ ] Secrets Manager works

**Functionality:**
- [ ] Multi-AZ distribution works
- [ ] Database connection pool works
- [ ] Performance is acceptable (< 200ms)

**Auto Scaling:**
- [ ] Manual scaling works
- [ ] Instance termination recovery works

**Disaster Recovery:**
- [ ] Instance failure recovery tested
- [ ] Zero downtime confirmed

---

## Final Check

```bash
echo "=== Production Infrastructure Status ==="
echo ""
echo "Application: http://$ALB_URL"
curl -s http://$ALB_URL/health | jq '{status, version, environment}'
echo ""
echo "ASG Status:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]' \
  --output text
echo ""
echo "RDS Status:"
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].[DBInstanceStatus,MultiAZ]' \
  --output text
echo ""
echo "Alarms in ALARM state:"
aws cloudwatch describe-alarms \
  --region $AWS_REGION \
  --alarm-name-prefix demo-app-prod \
  --state-value ALARM \
  --query 'MetricAlarms[].AlarmName' \
  --output text
echo ""
echo "✓ Production verification complete!"
```

## What to do if something fails?

### Application not responding
1. Check target health: `aws elbv2 describe-target-health --target-group-arn $TG_ARN`
2. Check logs: `aws logs tail /aws/ec2/demo-app-prod-application --follow`
3. Check security groups
4. Instance refresh: `aws autoscaling start-instance-refresh --auto-scaling-group-name $ASG_NAME`

### Alarms in ALARM state
1. Check reason: `aws cloudwatch describe-alarms --state-value ALARM`
2. Look at metrics in Dashboard
3. Check application logs

### Database connection failed
1. Check RDS status: `aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE`
2. Check security groups
3. Check secrets: `aws secretsmanager get-secret-value --secret-id demo-app-prod-db-creds`

### Email not arriving
1. Check subscription status
2. Check spam folder
3. Send test message through SNS
