# Testing Guide - Infrastructure and Auto Scaling

Guide for testing production infrastructure, Auto Scaling, monitoring, and high availability.

## 1. Auto Scaling Testing

### 1.1 CPU-Based Scaling Test

**Goal**: Verify that ASG scales under high CPU load.

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Connect to instance via SSM
aws ssm start-session --target $INSTANCE_ID --region eu-north-1

# On the instance, run CPU stress test
sudo yum install -y stress
stress --cpu 4 --timeout 600s  # 10 minutes load on 4 cores

# In another terminal, monitor scaling
watch -n 10 'aws autoscaling describe-auto-scaling-groups \
  --region eu-north-1 \
  --auto-scaling-group-names demo-app-prod-asg-* \
  --query "AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]" \
  --output text'
```

**Expected result**:
- CPU metric rises above 70%
- After 2-3 minutes, desired capacity increases
- CloudWatch alarm `demo-app-prod-cpu-high` transitions to ALARM
- New instance launches
- After stopping stress, CPU returns to normal
- Desired capacity decreases back to minimum

### 1.2 Request-Based Scaling Test

**Goal**: Verify scaling based on request count.

```bash
# Get ALB URL
ALB_URL=$(aws elbv2 describe-load-balancers \
  --region eu-north-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `prod`)].DNSName' \
  --output text)

# Run load test (requires apache-bench)
sudo apt-get install -y apache2-utils  # on Linux
# or
brew install httpie wrk  # on macOS

# Generate load
wrk -t12 -c400 -d5m http://$ALB_URL/health
# or
ab -n 100000 -c 50 http://$ALB_URL/health

# Monitor
watch -n 5 'echo "=== ALB Metrics ==="; \
aws cloudwatch get-metric-statistics \
  --region eu-north-1 \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=app/demo-app-prod-alb/* \
  --start-time $(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average'
```

**Expected result**:
- RequestCountPerTarget > 1000
- ASG adds instances
- Response time remains acceptable
- WAF may block if rate limit is exceeded

### 1.3 Manual Scaling Test

**Goal**: Verify that capacity can be changed manually.

```bash
# Increase desired capacity to 4
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --region eu-north-1 \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `prod`)].AutoScalingGroupName' \
  --output text)

aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 4 \
  --region eu-north-1

# Check scaling activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name $ASG_NAME \
  --region eu-north-1 \
  --max-records 5

# Revert back
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 2 \
  --region eu-north-1
```

## 2. High Availability Testing

### 2.1 Multi-AZ Failover Test

**Goal**: Verify that the application works when one AZ fails.

```bash
# View current distribution
aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone,PrivateIpAddress]' \
  --output table

# Terminate all instances in one AZ (simulate AZ failure)
INSTANCES_AZ_A=$(aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" \
       "Name=instance-state-name,Values=running" \
       "Name=availability-zone,Values=eu-north-1a" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

aws ec2 terminate-instances --instance-ids $INSTANCES_AZ_A --region eu-north-1

# Verify that ALB redirects traffic to remaining AZs
for i in {1..20}; do
  curl -s http://$ALB_URL/health | jq '.instance.az'
  sleep 1
done

# ASG should launch new instances in other AZs
watch -n 5 'aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running,pending" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,Placement.AvailabilityZone]" \
  --output table'
```

**Expected result**:
- Application is accessible without downtime
- ALB switches traffic to healthy targets
- ASG launches replacements in other AZs
- RDS Multi-AZ continues to work

### 2.2 RDS Failover Test

**Goal**: Verify automatic RDS failover.

```bash
# Force failover (WARNING: brief database downtime)
DB_INSTANCE=$(aws rds describe-db-instances \
  --region eu-north-1 \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `prod`)].DBInstanceIdentifier' \
  --output text)

echo "Initiating failover for $DB_INSTANCE (will have ~2 minutes of downtime)"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  aws rds reboot-db-instance \
    --db-instance-identifier $DB_INSTANCE \
    --force-failover-allowed \
    --region eu-north-1
fi

# Monitor status
watch -n 5 'aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region eu-north-1 \
  --query "DBInstances[0].[DBInstanceStatus,AvailabilityZone]" \
  --output text'

# Verify that application reconnects
for i in {1..60}; do
  STATUS=$(curl -s http://$ALB_URL/db | jq -r '.status')
  echo "$(date +%H:%M:%S) - DB Status: $STATUS"
  sleep 2
done
```

**Expected result**:
- RDS failover takes 1-2 minutes
- Application shows temporary connection errors
- Application automatically reconnects
- Endpoint remains the same (AWS DNS updates)

## 3. Instance Refresh Testing

### 3.1 Rolling Update Test

**Goal**: Update all instances without downtime.

```bash
# Start instance refresh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name $ASG_NAME \
  --region eu-north-1 \
  --preferences '{
    "MinHealthyPercentage": 100,
    "InstanceWarmup": 120
  }'

# Get refresh ID
REFRESH_ID=$(aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name $ASG_NAME \
  --region eu-north-1 \
  --query 'InstanceRefreshes[0].InstanceRefreshId' \
  --output text)

# Monitor progress
watch -n 10 'aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name $ASG_NAME \
  --region eu-north-1 \
  --instance-refresh-ids $REFRESH_ID \
  --query "InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]" \
  --output table'

# In a parallel window - check availability
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" http://$ALB_URL/health
  sleep 2
done
```

**Expected result**:
- MinHealthyPercentage: 100 = zero downtime
- Instances update one by one
- ALB always has healthy targets
- All HTTP requests return 200

## 4. WAF Testing

### 4.1 Rate Limiting Test

**Goal**: Verify that WAF blocks rate limit violations.

```bash
# Quickly send many requests from one IP
for i in {1..3000}; do
  curl -s http://$ALB_URL/ > /dev/null &
done

# Verify we get 403
curl -v http://$ALB_URL/

# View WAF metrics
aws cloudwatch get-metric-statistics \
  --region eu-north-1 \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --dimensions Name=WebACL,Value=demo-app-prod-web-acl \
              Name=Region,Value=eu-north-1 \
              Name=Rule,Value=RateLimitRule \
  --start-time $(date -u -d "10 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Expected result**:
- After ~2000 requests we get 403 Forbidden
- WAF alarm `demo-app-prod-waf-rate-limit` activates
- Block is lifted after 5 minutes

### 4.2 SQL Injection Test (MUST BE BLOCKED)

**Goal**: Verify that WAF blocks SQL injection.

```bash
# Test SQL injection (safe - only GET request)
curl -v "http://$ALB_URL/api/items?id=1' OR '1'='1"

# Should return 403 Forbidden
```

## 5. Monitoring & Alerts Testing

### 5.1 CloudWatch Alarms Test

**Goal**: Verify that alarms work and send notifications.

```bash
# View all alarms
aws cloudwatch describe-alarms \
  --region eu-north-1 \
  --alarm-name-prefix demo-app-prod \
  --query 'MetricAlarms[].[AlarmName,StateValue]' \
  --output table

# Forcefully trigger alarm (high CPU)
# ... use stress test from section 1.1 ...

# Check alarm history
aws cloudwatch describe-alarm-history \
  --region eu-north-1 \
  --alarm-name demo-app-prod-cpu-high \
  --history-item-type StateUpdate \
  --max-records 5
```

**Expected result**:
- Alarm transitions to ALARM state
- SNS topic receives message
- Email arrives at your-email@example.com

### 5.2 Application Logs Test

**Goal**: Verify that logs are collected in CloudWatch.

```bash
# View recent logs
aws logs tail /aws/ec2/demo-app-prod-application \
  --region eu-north-1 \
  --follow

# Generate test requests
for i in {1..50}; do
  curl -s http://$ALB_URL/ > /dev/null
  curl -s http://$ALB_URL/api/items > /dev/null
done

# Search for ERROR in logs
aws logs filter-log-events \
  --region eu-north-1 \
  --log-group-name /aws/ec2/demo-app-prod-application \
  --filter-pattern "ERROR" \
  --max-items 10
```

## 6. Disaster Recovery Testing

### 6.1 Complete Infrastructure Recovery

**Goal**: Verify recovery from complete failure.

```bash
# 1. Take snapshot of current state
terraform -chdir=terraform/environments/prod show -json > backup-state.json

# 2. Destroy infrastructure (NOT in production!!!)
# terraform -chdir=terraform/environments/prod destroy -auto-approve

# 3. Restore
# terraform -chdir=terraform/environments/prod apply -auto-approve

# 4. Verify everything works
make smoke-test ENV=prod
```

### 6.2 RDS Snapshot Restore

**Goal**: Verify database restore from snapshot.

```bash
# Create snapshot manually
aws rds create-db-snapshot \
  --db-instance-identifier $DB_INSTANCE \
  --db-snapshot-identifier demo-app-prod-manual-snapshot-$(date +%Y%m%d) \
  --region eu-north-1

# View snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier $DB_INSTANCE \
  --region eu-north-1 \
  --query 'DBSnapshots[].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table
```

## 7. Security Testing

### 7.1 Network Isolation Test

**Goal**: Verify that private resources are not accessible from outside.

```bash
# RDS endpoint should not be publicly accessible
DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region eu-north-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Should timeout (RDS in private subnet)
timeout 5 nc -zv $DB_ENDPOINT 5432 || echo "✓ RDS not publicly accessible (correct)"

# Applications accessible only through ALB
INSTANCE_IP=$(aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

# Should timeout (EC2 in private subnet)
timeout 5 curl http://$INSTANCE_IP:5001 || echo "✓ EC2 not publicly accessible (correct)"
```

### 7.2 IAM Permissions Test

**Goal**: Verify that instances have minimum necessary permissions.

```bash
# Connect to instance
aws ssm start-session --target $INSTANCE_ID --region eu-north-1

# On the instance, try to perform forbidden actions
aws ec2 describe-instances  # Should be denied
aws s3 ls                    # Should be denied

# Allowed actions
aws secretsmanager get-secret-value --secret-id demo-app-prod-db-creds  # ✓
aws ecr get-login-password  # ✓
aws logs put-log-events     # ✓
```

## 8. Performance Testing

### 8.1 Database Performance

**Goal**: Verify database performance.

```bash
# API endpoint for creating records
for i in {1..1000}; do
  curl -X POST http://$ALB_URL/api/items \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"item-$i\",\"value\":$i}" &
done
wait

# Check RDS Performance Insights
echo "Open: https://console.aws.amazon.com/rds/home?region=eu-north-1#performance-insights:resourceId=$DB_INSTANCE"

# Check connection pool
curl -s http://$ALB_URL/db | jq
```

### 8.2 Latency Test

**Goal**: Measure latencies at different stages.

```bash
# ALB latency
curl -w "@curl-format.txt" -o /dev/null -s http://$ALB_URL/health

# Create curl-format.txt:
cat > curl-format.txt << 'EOF'
    time_namelookup:  %{time_namelookup}s\n
       time_connect:  %{time_connect}s\n
    time_appconnect:  %{time_appconnect}s\n
   time_pretransfer:  %{time_pretransfer}s\n
      time_redirect:  %{time_redirect}s\n
 time_starttransfer:  %{time_starttransfer}s\n
                    ----------\n
         time_total:  %{time_total}s\n
EOF

# CloudWatch ALB metrics
aws cloudwatch get-metric-statistics \
  --region eu-north-1 \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=app/demo-app-prod-alb/* \
  --start-time $(date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  --query 'Datapoints[*].[Timestamp,Average,Maximum]' \
  --output table
```

## Testing checklist before production release

- [ ] Auto Scaling on CPU load works
- [ ] Auto Scaling on request load works
- [ ] Multi-AZ failover without downtime
- [ ] RDS failover succeeds
- [ ] Instance refresh without downtime
- [ ] WAF blocks rate limit
- [ ] WAF blocks SQL injection
- [ ] CloudWatch alarms activate
- [ ] Email notifications arrive
- [ ] Logs are written to CloudWatch
- [ ] RDS snapshots are created automatically
- [ ] Private resources are not accessible from outside
- [ ] IAM permissions are minimal
- [ ] Performance is acceptable (< 200ms)
- [ ] Health checks pass

## Test Automation

Scripts can be created for automation:

```bash
# scripts/run-infrastructure-tests.sh
#!/bin/bash
set -e

ENV=${1:-prod}
REGION=${2:-eu-north-1}

echo "Running infrastructure tests for $ENV in $REGION..."

# 1. Health checks
echo "1. Health checks..."
make health-check ENV=$ENV

# 2. Smoke tests
echo "2. Smoke tests..."
make smoke-test ENV=$ENV

# 3. Check alarms
echo "3. Checking CloudWatch alarms..."
aws cloudwatch describe-alarms \
  --region $REGION \
  --alarm-name-prefix demo-app-$ENV \
  --state-value ALARM \
  --query 'MetricAlarms[].AlarmName'

# 4. Check target health
echo "4. Checking target health..."
TG_ARN=$(aws elbv2 describe-target-groups \
  --region $REGION \
  --query "TargetGroups[?contains(TargetGroupName, '$ENV')].TargetGroupArn" \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $REGION \
  --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`]'

echo "✅ All tests passed!"
```
