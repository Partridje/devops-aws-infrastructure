# Operations Runbook

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Initial Setup](#initial-setup)
- [Deployment Procedures](#deployment-procedures)
- [Routine Operations](#routine-operations)
- [Monitoring and Alerting](#monitoring-and-alerting)
- [Troubleshooting](#troubleshooting)
- [Disaster Recovery](#disaster-recovery)
- [Maintenance Procedures](#maintenance-procedures)
- [Emergency Procedures](#emergency-procedures)
- [Useful Commands](#useful-commands)
- [Contacts and Escalation](#contacts-and-escalation)

## Overview

This runbook provides step-by-step operational procedures for the DevOps AWS Infrastructure project. It is intended for DevOps engineers, SREs, and on-call personnel responsible for maintaining and operating the infrastructure.

### System Components

- **VPC**: Multi-AZ networking with public/private/database subnets
- **ALB**: Application Load Balancer for traffic distribution
- **ASG**: Auto Scaling Group with EC2 instances running Flask application
- **RDS**: PostgreSQL database (Multi-AZ in production)
- **ECR**: Container registry for Docker images
- **CloudWatch**: Monitoring, logging, and alerting
- **Secrets Manager**: Secure credential storage

### Service Level Objectives (SLOs)

| Metric | Target | Measurement Period |
|--------|--------|-------------------|
| **Availability** | 99.9% (production) | Monthly |
| **Response Time** | p95 < 500ms | 5 minutes |
| **Error Rate** | < 0.1% | 5 minutes |
| **Database Latency** | p95 < 100ms | 5 minutes |

## Getting Started

### Prerequisites

Before performing any operations, ensure you have:

1. **AWS CLI configured**:
   ```bash
   aws configure
   aws sts get-caller-identity  # Verify credentials
   ```

2. **Terraform installed** (v1.5.0+, recommended 1.9+):
   ```bash
   terraform version
   ```

3. **Docker installed** (for local testing):
   ```bash
   docker --version
   ```

4. **Required permissions**:
   - EC2: Describe, Start, Stop instances
   - RDS: Describe, Modify, Create snapshots
   - CloudWatch: Read logs, metrics, alarms
   - Secrets Manager: Read secrets
   - SSM: Start sessions

5. **Access to tools**:
   - GitHub repository access
   - AWS Console access (with MFA)
   - On-call rotation schedule (PagerDuty/Opsgenie)

### Quick Reference

| Resource | Dev | Prod |
|----------|-----|------|
| **Region** | eu-north-1 | eu-north-1 |
| **VPC CIDR** | 10.0.0.0/16 | 10.0.0.0/16 |
| **AZs** | 2 | 3 |
| **ASG Min/Max** | 1-2 | 2-10 |
| **Instance Type** | t3.micro | t3.small |
| **RDS Instance** | db.t3.micro (single-AZ) | db.t3.small (Multi-AZ) |

## Initial Setup

### First-Time Infrastructure Deployment

#### Step 1: Setup Terraform Backend

```bash
# Clone repository
git clone <repository-url>
cd devops-aws-infrastructure

# Create S3 backend for Terraform state
cd scripts
chmod +x setup-terraform-backend.sh
./setup-terraform-backend.sh

# Note the bucket name and DynamoDB table name
# Example output:
# ✅ S3 bucket created: terraform-state-demo-flask-app-123456789012
# ✅ DynamoDB table created: terraform-state-lock-demo-flask-app
```

#### Step 2: Setup GitHub OIDC (for CI/CD)

```bash
# Create GitHub Actions OIDC provider
chmod +x setup-github-oidc.sh
./setup-github-oidc.sh

# Note the IAM role ARN
# Example output:
# ✅ OIDC provider created: arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com
# ✅ IAM role created: arn:aws:iam::123456789012:role/github-actions-role
```

#### Step 3: Configure GitHub Secrets

Add the following secrets to your GitHub repository (Settings → Secrets):

```
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/github-actions-role
```

#### Step 4: Update Backend Configuration

```bash
# Update backend configuration in environment files
cd ../terraform/environments/dev

# Edit backend.tf (if not already configured)
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket         = "terraform-state-demo-flask-app-123456789012"
    key            = "dev/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-state-lock-demo-flask-app"
    encrypt        = true
  }
}
EOF

# Repeat for prod environment
cd ../prod
# Update backend.tf with key = "prod/terraform.tfstate"
```

#### Step 5: Generate SSL Certificate (for HTTPS)

```bash
# For development/testing only
cd ../../../scripts
chmod +x generate-cert.sh
./generate-cert.sh

# For production, use AWS Certificate Manager:
# 1. Request certificate in ACM console
# 2. Validate domain ownership (DNS or email)
# 3. Note certificate ARN
```

#### Step 6: Deploy Development Environment

```bash
cd ../terraform/environments/dev

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit variables (important!)
vim terraform.tfvars

# Required changes:
# - project_name: Your project name
# - environment: dev
# - alert_email: Your email for CloudWatch alarms
# - allowed_cidr_blocks: Your IP address for security

# Initialize Terraform
terraform init

# Review plan
terraform plan -out=tfplan

# Apply (after reviewing plan)
terraform apply tfplan

# Save outputs
terraform output > outputs.txt
```

**Expected Duration**: 15-20 minutes for initial deployment

#### Step 7: Verify Deployment

```bash
# Get ALB URL from outputs
ALB_URL=$(terraform output -raw alb_url)

# Wait 2-3 minutes for instances to become healthy
sleep 180

# Test health endpoint
curl -f "$ALB_URL/health"

# Expected output:
# {
#   "status": "healthy",
#   "database": "connected",
#   "timestamp": "2024-01-15T12:00:00Z"
# }
```

## Deployment Procedures

### Deploying Infrastructure Changes

#### Via GitHub Actions (Recommended)

1. **Create feature branch**:
   ```bash
   git checkout -b feature/update-instance-type
   ```

2. **Make changes** to Terraform files

3. **Commit and push**:
   ```bash
   git add .
   git commit -m "Update instance type to t3.small"
   git push origin feature/update-instance-type
   ```

4. **Create pull request** on GitHub

5. **Review Terraform plan** in PR comments (posted by GitHub Actions)

6. **Merge to main** (after approval)

7. **Monitor deployment**:
   - Development environment deploys automatically
   - Production requires manual workflow dispatch

8. **Trigger production deployment**:
   - Go to Actions → Terraform Apply workflow
   - Click "Run workflow"
   - Select environment: "prod"
   - Confirm deployment

#### Manual Deployment (Emergency)

```bash
cd terraform/environments/dev  # or prod

# Pull latest code
git pull origin main

# Plan
terraform plan -out=tfplan

# Review plan carefully
terraform show tfplan

# Apply (with confirmation)
terraform apply tfplan

# Verify
terraform output
```

### Deploying Application Changes

#### Via GitHub Actions (Recommended)

1. **Make code changes** in `app/src/app.py`

2. **Commit and push**:
   ```bash
   git add app/
   git commit -m "Add new API endpoint for user management"
   git push origin main
   ```

3. **GitHub Actions workflow**:
   - Builds Docker image
   - Scans with Trivy
   - Pushes to ECR
   - Triggers ASG instance refresh

4. **Monitor deployment**:
   ```bash
   # Watch ASG instance refresh status
   aws autoscaling describe-instance-refreshes \
     --auto-scaling-group-name demo-flask-app-dev-asg \
     --max-records 1

   # Monitor logs
   aws logs tail /aws/ec2/demo-flask-app-dev --follow
   ```

#### Manual Application Deployment

```bash
# Build Docker image locally
cd app
docker build -t demo-flask-app:latest .

# Tag for ECR
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
docker tag demo-flask-app:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.eu-north-1.amazonaws.com/demo-flask-app:latest

# Login to ECR
aws ecr get-login-password --region eu-north-1 | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.eu-north-1.amazonaws.com

# Push image
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.eu-north-1.amazonaws.com/demo-flask-app:latest

# Trigger instance refresh
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?Tags[?Key=='Environment' && Value=='dev']].AutoScalingGroupName" \
  --output text | head -n1)

aws autoscaling start-instance-refresh \
  --auto-scaling-group-name ${ASG_NAME} \
  --preferences '{"MinHealthyPercentage": 90, "InstanceWarmup": 300}'

# Monitor refresh
watch -n 10 "aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name ${ASG_NAME} \
  --max-records 1"
```

### Rolling Back Deployments

#### Rollback Infrastructure

```bash
# Option 1: Revert to previous Terraform state
cd terraform/environments/prod

# List state versions
aws s3api list-object-versions \
  --bucket terraform-state-demo-flask-app-123456789012 \
  --prefix prod/terraform.tfstate

# Download previous version
aws s3api get-object \
  --bucket terraform-state-demo-flask-app-123456789012 \
  --key prod/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup

# Restore (use with caution!)
# Better: Use git revert and re-apply

# Option 2: Git revert and re-deploy
git revert <COMMIT_SHA>
git push origin main
# GitHub Actions will re-deploy previous version
```

#### Rollback Application

```bash
# Option 1: Re-deploy previous Docker image
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# List image tags
aws ecr describe-images \
  --repository-name demo-flask-app \
  --query 'sort_by(imageDetails,& imagePushedAt)[-10:].imageTags' \
  --output table

# Update user data to use specific image tag
# Edit terraform/modules/ec2/user_data.sh:
# IMAGE_TAG="<PREVIOUS_COMMIT_SHA>"

# Re-deploy
terraform apply

# Option 2: Cancel instance refresh (if in progress)
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?Tags[?Key=='Environment' && Value=='prod']].AutoScalingGroupName" \
  --output text | head -n1)

aws autoscaling cancel-instance-refresh \
  --auto-scaling-group-name ${ASG_NAME}

# Manually replace instances with previous image
# (Complex - prefer Option 1)
```

## Routine Operations

### Daily Operations Checklist

**Morning Checklist** (10 minutes):

```bash
# 1. Check CloudWatch Dashboard
aws cloudwatch get-dashboard \
  --dashboard-name demo-flask-app-prod-dashboard

# Open in browser: https://console.aws.amazon.com/cloudwatch/

# 2. Review alarms
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --query 'MetricAlarms[*].[AlarmName,StateReason]' \
  --output table

# 3. Check application health
ALB_URL=$(cd terraform/environments/prod && terraform output -raw alb_url)
curl -f "$ALB_URL/health" | jq .

# 4. Review error logs (last 1 hour)
aws logs tail /aws/ec2/demo-flask-app-prod \
  --since 1h \
  --filter-pattern '{ $.level = "ERROR" }' \
  --format short

# 5. Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-prod-db \
  --query 'DBInstances[0].[DBInstanceStatus,MultiAZ,StorageType,AllocatedStorage]' \
  --output table

# 6. Review GuardDuty findings (if enabled)
aws guardduty list-findings --detector-id <detector-id> \
  --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}'
```

### Weekly Operations Tasks

**Monday** (30 minutes):

1. **Review CloudWatch Insights trends**:
   ```bash
   # Run pre-defined queries
   aws logs start-query \
     --log-group-name /aws/ec2/demo-flask-app-prod \
     --start-time $(date -u -d '7 days ago' +%s) \
     --end-time $(date -u +%s) \
     --query-string 'fields @timestamp, @message
       | filter level = "ERROR"
       | stats count() by bin(5m)
       | sort @timestamp desc'
   ```

2. **Check for security updates**:
   ```bash
   # Review Trivy scan results from latest CI run
   # Check for CVEs in GitHub Security tab
   ```

3. **Review IAM access**:
   ```bash
   # Generate credential report
   aws iam generate-credential-report
   aws iam get-credential-report --output text | base64 -d > credential-report.csv

   # Review for unused credentials (>90 days)
   ```

### Monthly Operations Tasks

**First Monday** (2 hours):

1. **Update dependencies**:
   ```bash
   cd app

   # Update Python packages
   pip list --outdated
   # Review and update requirements.txt

   # Update Terraform providers
   cd ../terraform
   terraform init -upgrade
   ```

2. **Test backup restoration**:
   ```bash
   # Create test snapshot
   aws rds create-db-snapshot \
     --db-instance-identifier demo-flask-app-prod-db \
     --db-snapshot-identifier manual-backup-$(date +%Y%m%d)

   # Restore to test instance (see Disaster Recovery section)
   ```

3. **Review cost optimization**:
   ```bash
   # Check AWS Cost Explorer
   aws ce get-cost-and-usage \
     --time-period Start=$(date -u -d '1 month ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
     --granularity MONTHLY \
     --metrics UnblendedCost \
     --group-by Type=SERVICE
   ```

4. **Security audit**:
   ```bash
   # Run Prowler (AWS security assessment)
   # docker run -v ~/.aws:/root/.aws prowler/prowler -M csv

   # Review security group rules
   aws ec2 describe-security-groups \
     --filters "Name=tag:Environment,Values=prod" \
     --query 'SecurityGroups[*].[GroupName,IpPermissions]'
   ```

## Monitoring and Alerting

### CloudWatch Dashboard

**Access Dashboard**:
```bash
# Get dashboard URL
cd terraform/environments/prod
terraform output -raw cloudwatch_dashboard_url

# Or via AWS CLI
aws cloudwatch get-dashboard \
  --dashboard-name demo-flask-app-prod-dashboard
```

**Key Metrics to Monitor**:

1. **ALB Metrics**:
   - `TargetResponseTime` (p50, p95, p99)
   - `HTTPCode_Target_2XX_Count`
   - `HTTPCode_Target_5XX_Count`
   - `UnHealthyHostCount`
   - `ActiveConnectionCount`

2. **ASG Metrics**:
   - `GroupDesiredCapacity`
   - `GroupInServiceInstances`
   - `GroupMinSize` / `GroupMaxSize`

3. **EC2 Metrics**:
   - `CPUUtilization`
   - `NetworkIn` / `NetworkOut`
   - `StatusCheckFailed`

4. **RDS Metrics**:
   - `CPUUtilization`
   - `DatabaseConnections`
   - `FreeStorageSpace`
   - `ReadLatency` / `WriteLatency`
   - `ReplicaLag` (if using read replicas)

### CloudWatch Alarms

**Critical Alarms** (page on-call):

- `UnHealthyHostCount` > 0 for 5 minutes
- `HTTPCode_Target_5XX_Count` > 50 in 5 minutes
- `DatabaseCPU` > 90% for 10 minutes
- `DatabaseStorageSpace` < 10GB
- `TargetResponseTime` p95 > 1000ms for 10 minutes

**Warning Alarms** (email only):

- `CPUUtilization` > 70% for 15 minutes
- `DatabaseConnections` > 80% of max
- `TargetResponseTime` p95 > 500ms for 15 minutes

**Acknowledge Alarm**:
```bash
# Get alarm details
aws cloudwatch describe-alarms \
  --alarm-names "demo-flask-app-prod-unhealthy-hosts"

# Disable alarm temporarily (during maintenance)
aws cloudwatch disable-alarm-actions \
  --alarm-names "demo-flask-app-prod-unhealthy-hosts"

# Re-enable after maintenance
aws cloudwatch enable-alarm-actions \
  --alarm-names "demo-flask-app-prod-unhealthy-hosts"
```

### Log Analysis

**Search logs for errors**:
```bash
# Recent errors (last hour)
aws logs tail /aws/ec2/demo-flask-app-prod \
  --since 1h \
  --filter-pattern '{ $.level = "ERROR" }' \
  --format short

# Specific time range
aws logs filter-log-events \
  --log-group-name /aws/ec2/demo-flask-app-prod \
  --start-time $(date -u -d '2024-01-15 10:00:00' +%s)000 \
  --end-time $(date -u -d '2024-01-15 11:00:00' +%s)000 \
  --filter-pattern '{ $.level = "ERROR" }'
```

**CloudWatch Insights queries**:

```sql
-- Top 10 error messages
fields @timestamp, level, msg, error
| filter level = "ERROR"
| stats count() as error_count by msg
| sort error_count desc
| limit 10

-- Response time percentiles
fields @timestamp, response_time_ms
| filter ispresent(response_time_ms)
| stats avg(response_time_ms), pct(response_time_ms, 50), pct(response_time_ms, 95), pct(response_time_ms, 99)

-- Request volume over time
fields @timestamp
| stats count() as request_count by bin(5m)

-- Slow requests (>1 second)
fields @timestamp, method, path, response_time_ms
| filter response_time_ms > 1000
| sort @timestamp desc
| limit 100
```

**Run Insights query**:
```bash
QUERY_ID=$(aws logs start-query \
  --log-group-name /aws/ec2/demo-flask-app-prod \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, level, msg | filter level = "ERROR" | limit 20' \
  --query 'queryId' \
  --output text)

# Wait for query to complete
sleep 5

# Get results
aws logs get-query-results --query-id $QUERY_ID
```

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: High 5xx Error Rate

**Symptoms**:
- CloudWatch alarm: `demo-flask-app-prod-high-5xx-errors`
- Users reporting errors
- Dashboard shows spike in `HTTPCode_Target_5XX_Count`

**Investigation**:
```bash
# 1. Check application logs
aws logs tail /aws/ec2/demo-flask-app-prod --since 30m --filter-pattern "500"

# 2. Check instance health
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?Tags[?Key=='Environment' && Value=='prod']].AutoScalingGroupName" \
  --output text | head -n1)

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ${ASG_NAME} \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
  --output table

# 3. Check database connectivity
aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-prod-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]'

# 4. Test database connection from instance
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ${ASG_NAME} \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

aws ssm start-session --target ${INSTANCE_ID}
# In SSM session:
# psql -h <DB_HOST> -U <DB_USER> -d <DB_NAME> -c "SELECT 1;"
```

**Common Root Causes**:

1. **Database connection exhaustion**:
   ```bash
   # Check current connections
   aws rds describe-db-log-files \
     --db-instance-identifier demo-flask-app-prod-db

   # Solution: Increase max_connections in parameter group or scale application
   ```

2. **Memory exhaustion on instances**:
   ```bash
   # Check memory metrics
   aws cloudwatch get-metric-statistics \
     --namespace CWAgent \
     --metric-name mem_used_percent \
     --dimensions Name=AutoScalingGroupName,Value=${ASG_NAME} \
     --start-time $(date -u -d '1 hour ago' +%s) \
     --end-time $(date -u +%s) \
     --period 300 \
     --statistics Average

   # Solution: Increase instance size or fix memory leak
   ```

3. **Unhandled exception in code**:
   ```bash
   # Review error traces
   aws logs tail /aws/ec2/demo-flask-app-prod \
     --since 30m \
     --filter-pattern '{ $.level = "ERROR" }' \
     --format short

   # Solution: Deploy fix via CI/CD
   ```

#### Issue 2: Database Connection Failures

**Symptoms**:
- `/health` endpoint returns unhealthy
- Logs show `psycopg2.OperationalError`
- CloudWatch alarm: `demo-flask-app-prod-db-connections-high`

**Investigation**:
```bash
# 1. Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-prod-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,Endpoint.Port]'

# 2. Check security group rules
DB_SG=$(aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-prod-db \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

aws ec2 describe-security-groups --group-ids ${DB_SG}

# 3. Test connectivity from application instance
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ${ASG_NAME} \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

aws ssm start-session --target ${INSTANCE_ID}
# In SSM session:
# nc -zv <DB_HOST> 5432
# telnet <DB_HOST> 5432

# 4. Check database credentials
SECRET_ARN=$(cd terraform/environments/prod && terraform output -raw db_secret_arn)

aws secretsmanager get-secret-value \
  --secret-id ${SECRET_ARN} \
  --query SecretString \
  --output text | jq .
```

**Solutions**:

1. **RDS instance unavailable**:
   ```bash
   # Check for maintenance or failover
   aws rds describe-events \
     --source-identifier demo-flask-app-prod-db \
     --duration 60

   # Wait for RDS to recover, or force failover (Multi-AZ only)
   aws rds reboot-db-instance \
     --db-instance-identifier demo-flask-app-prod-db \
     --force-failover
   ```

2. **Incorrect credentials**:
   ```bash
   # Rotate secret
   aws secretsmanager rotate-secret \
     --secret-id ${SECRET_ARN}

   # Trigger instance refresh to pick up new credentials
   aws autoscaling start-instance-refresh \
     --auto-scaling-group-name ${ASG_NAME}
   ```

3. **Security group misconfiguration**:
   ```bash
   # Verify application security group can reach database
   APP_SG=$(aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names ${ASG_NAME} \
     --query 'AutoScalingGroups[0].Instances[0].SecurityGroups[0]' \
     --output text)

   # Check if APP_SG is allowed in DB_SG ingress rules
   aws ec2 describe-security-groups --group-ids ${DB_SG} \
     --query 'SecurityGroups[0].IpPermissions'

   # If missing, add via Terraform (don't modify manually)
   ```

#### Issue 3: Auto Scaling Not Working

**Symptoms**:
- High CPU but no new instances launched
- Or: Instances launched but immediately terminated

**Investigation**:
```bash
# 1. Check ASG activity history
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name ${ASG_NAME} \
  --max-records 20 \
  --query 'Activities[*].[StartTime,StatusCode,StatusMessage,Description]' \
  --output table

# 2. Check ASG current state
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ${ASG_NAME} \
  --query 'AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity,Instances[*].HealthStatus]'

# 3. Check scaling policies
aws autoscaling describe-policies \
  --auto-scaling-group-name ${ASG_NAME}

# 4. Check CloudWatch alarms for scaling policies
aws cloudwatch describe-alarms \
  --alarm-name-prefix ${ASG_NAME}
```

**Common Issues**:

1. **Reached max size**:
   ```bash
   # Temporarily increase max size
   aws autoscaling update-auto-scaling-group \
     --auto-scaling-group-name ${ASG_NAME} \
     --max-size 15

   # Permanent fix: Update Terraform
   # terraform/environments/prod/main.tf: max_size = 15
   ```

2. **Launch template issue**:
   ```bash
   # Check recent failed launches
   aws ec2 describe-instances \
     --filters "Name=tag:aws:autoscaling:groupName,Values=${ASG_NAME}" \
     --query 'Reservations[*].Instances[?State.Name==`terminated`].[InstanceId,StateTransitionReason]' \
     --output table

   # Review user data logs (if instance lived long enough)
   aws ssm start-session --target <INSTANCE_ID>
   # tail -f /var/log/user-data.log
   ```

3. **Health check failures**:
   ```bash
   # Check target group health
   TG_ARN=$(cd terraform/environments/prod && terraform output -raw target_group_arn)

   aws elbv2 describe-target-health \
     --target-group-arn ${TG_ARN}

   # Common causes:
   # - Application not starting (check user data)
   # - Health check path incorrect (/health must return 200)
   # - Health check timeout too short
   ```

#### Issue 4: SSL/TLS Certificate Issues

**Symptoms**:
- HTTPS endpoint returns certificate error
- Browser shows "Not Secure"
- Alarm: `demo-flask-app-prod-cert-expiring`

**Investigation**:
```bash
# 1. Check certificate expiry
CERT_ARN=$(cd terraform/environments/prod && terraform output -raw ssl_certificate_arn)

aws acm describe-certificate \
  --certificate-arn ${CERT_ARN} \
  --query 'Certificate.[Status,NotAfter,DomainValidationOptions]'

# 2. Test HTTPS connection
ALB_URL=$(cd terraform/environments/prod && terraform output -raw alb_url)
openssl s_client -connect ${ALB_URL#https://}:443 -servername ${ALB_URL#https://} </dev/null

# 3. Check ALB listener
ALB_ARN=$(cd terraform/environments/prod && terraform output -raw alb_arn)

aws elbv2 describe-listeners \
  --load-balancer-arn ${ALB_ARN} \
  --query 'Listeners[?Port==`443`]'
```

**Solutions**:

1. **Certificate expired**:
   ```bash
   # ACM auto-renews if DNS validation configured
   # If failed, manually re-validate or request new certificate

   # Request new certificate
   NEW_CERT_ARN=$(aws acm request-certificate \
     --domain-name example.com \
     --validation-method DNS \
     --query 'CertificateArn' \
     --output text)

   # Update Terraform
   # terraform/environments/prod/terraform.tfvars:
   # ssl_certificate_arn = "<NEW_CERT_ARN>"

   # Apply
   terraform apply
   ```

2. **Self-signed certificate** (dev/test only):
   ```bash
   # Regenerate certificate
   cd scripts
   ./generate-cert.sh

   # Re-deploy infrastructure with new certificate
   ```

### Performance Troubleshooting

#### Slow Response Times

**Investigation**:
```bash
# 1. Check application response time metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=<ALB_FULL_NAME> \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --period 300 \
  --statistics Average,Maximum \
  --extended-statistics p95,p99

# 2. Check database query performance
# Use RDS Performance Insights or CloudWatch Logs

# 3. Check if instances are CPU-bound
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=${ASG_NAME} \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --period 300 \
  --statistics Average,Maximum

# 4. Analyze slow requests in logs
aws logs start-query \
  --log-group-name /aws/ec2/demo-flask-app-prod \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, path, response_time_ms, db_query_time_ms
    | filter response_time_ms > 1000
    | sort response_time_ms desc
    | limit 50'
```

**Common Optimizations**:

1. **Database query optimization**:
   ```sql
   -- Add indexes for frequently queried columns
   CREATE INDEX idx_items_created_at ON items(created_at);
   ```

2. **Connection pool tuning**:
   ```python
   # app/src/app.py
   # Increase pool size if seeing connection waits
   DB_POOL_MIN_CONN = 5  # from 2
   DB_POOL_MAX_CONN = 20  # from 10
   ```

3. **Caching** (future enhancement):
   ```python
   # Add Redis/ElastiCache for frequently accessed data
   ```

4. **Vertical scaling**:
   ```bash
   # Increase instance size
   # terraform/environments/prod/main.tf:
   # instance_type = "t3.medium"  # from t3.small
   ```

## Disaster Recovery

### RDS Database Recovery

#### Point-in-Time Restore

**Scenario**: Accidental data deletion, corruption

```bash
# 1. Identify restore point
aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-prod-db \
  --query 'DBInstances[0].LatestRestorableTime'

# Example: 2024-01-15T14:30:00Z

# 2. Restore to new instance
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier demo-flask-app-prod-db \
  --target-db-instance-identifier demo-flask-app-prod-db-restored \
  --restore-time 2024-01-15T14:30:00Z

# 3. Wait for restore to complete (10-30 minutes)
aws rds wait db-instance-available \
  --db-instance-identifier demo-flask-app-prod-db-restored

# 4. Verify data
RESTORED_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-prod-db-restored \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Connect and verify (from bastion or instance)
psql -h ${RESTORED_ENDPOINT} -U <DB_USER> -d <DB_NAME> -c "SELECT COUNT(*) FROM items;"

# 5. Promote restored instance to production
# Option A: Update Secrets Manager to point to new endpoint (requires app restart)
# Option B: Rename instances (requires downtime)

# 6. Delete old instance (after confirming data integrity)
aws rds delete-db-instance \
  --db-instance-identifier demo-flask-app-prod-db \
  --skip-final-snapshot  # or --final-snapshot-identifier for safety
```

#### Restore from Snapshot

**Scenario**: Major data loss, longer-term recovery

```bash
# 1. List available snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier demo-flask-app-prod-db \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# 2. Restore from specific snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier demo-flask-app-prod-db-restored \
  --db-snapshot-identifier rds:demo-flask-app-prod-db-2024-01-15-06-00

# 3. Follow steps 3-6 from Point-in-Time Restore above
```

### Complete Infrastructure Recovery

**Scenario**: Region failure, account compromise, complete loss

```bash
# 1. Ensure Terraform state backup exists
aws s3 ls s3://terraform-state-demo-flask-app-123456789012/prod/

# 2. Restore RDS from snapshot (if needed)
# Follow RDS recovery procedure above

# 3. Recreate infrastructure from Terraform
cd terraform/environments/prod

# If state file lost, import existing resources
# terraform import aws_vpc.main vpc-xxxxx
# terraform import aws_db_instance.main demo-flask-app-prod-db

# Otherwise, just re-apply
terraform init
terraform plan
terraform apply

# 4. Verify all components
make health-check ENV=prod
```

### Database Backup Best Practices

**Automated Backups** (configured in Terraform):
- Daily automated snapshots (retention: 30 days prod, 7 days dev)
- Point-in-time recovery window: Last N days

**Manual Backups** (before major changes):
```bash
# Create manual snapshot before risky operation
aws rds create-db-snapshot \
  --db-instance-identifier demo-flask-app-prod-db \
  --db-snapshot-identifier manual-backup-before-migration-$(date +%Y%m%d-%H%M%S)

# Export snapshot to S3 for long-term retention
aws rds start-export-task \
  --export-task-identifier export-$(date +%Y%m%d) \
  --source-arn arn:aws:rds:eu-north-1:123456789012:snapshot:manual-backup-before-migration-20240115-120000 \
  --s3-bucket-name database-backups \
  --iam-role-arn arn:aws:iam::123456789012:role/rds-s3-export-role \
  --kms-key-id arn:aws:kms:eu-north-1:123456789012:key/abcd1234-ab12-cd34-ef56-abcdef123456
```

**Cross-Region Replication** (future enhancement):
```hcl
# terraform/modules/rds/main.tf
resource "aws_db_instance_automated_backups_replication" "default" {
  source_db_instance_arn = aws_db_instance.main.arn
  kms_key_id            = var.backup_kms_key_id
}
```

## Maintenance Procedures

### Planned Maintenance Window

**Standard Maintenance Window**: Sunday 02:00-05:00 UTC

**Pre-Maintenance Checklist**:
```bash
# 1. Announce maintenance (24-48 hours notice)
# 2. Create backup
aws rds create-db-snapshot \
  --db-instance-identifier demo-flask-app-prod-db \
  --db-snapshot-identifier pre-maintenance-$(date +%Y%m%d)

# 3. Disable CloudWatch alarms (to prevent false alerts)
aws cloudwatch disable-alarm-actions \
  --alarm-names \
    demo-flask-app-prod-unhealthy-hosts \
    demo-flask-app-prod-high-5xx-errors

# 4. Document current state
cd terraform/environments/prod
terraform output > pre-maintenance-outputs.txt
```

**Post-Maintenance Checklist**:
```bash
# 1. Verify all services healthy
make health-check ENV=prod

# 2. Re-enable alarms
aws cloudwatch enable-alarm-actions \
  --alarm-names \
    demo-flask-app-prod-unhealthy-hosts \
    demo-flask-app-prod-high-5xx-errors

# 3. Monitor for 30 minutes
watch -n 30 'curl -f $(cd terraform/environments/prod && terraform output -raw alb_url)/health'

# 4. Document changes
# Update CHANGELOG.md with maintenance summary
```

### Database Maintenance

#### RDS Parameter Group Changes

```bash
# 1. Create new parameter group
aws rds create-db-parameter-group \
  --db-parameter-group-name demo-flask-app-prod-pg-v2 \
  --db-parameter-group-family postgres15 \
  --description "Updated parameter group with optimizations"

# 2. Modify parameters
aws rds modify-db-parameter-group \
  --db-parameter-group-name demo-flask-app-prod-pg-v2 \
  --parameters \
    "ParameterName=max_connections,ParameterValue=200,ApplyMethod=pending-reboot" \
    "ParameterName=shared_buffers,ParameterValue='{DBInstanceClassMemory/4096}',ApplyMethod=pending-reboot"

# 3. Apply to RDS instance (via Terraform)
# terraform/modules/rds/main.tf:
# parameter_group_name = "demo-flask-app-prod-pg-v2"

terraform apply

# 4. Reboot to apply pending changes
aws rds reboot-db-instance \
  --db-instance-identifier demo-flask-app-prod-db

# 5. Monitor after reboot
aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-prod-db \
  --query 'DBInstances[0].[DBInstanceStatus,DBParameterGroups[0].ParameterApplyStatus]'
```

#### RDS Minor Version Upgrade

```bash
# 1. Check available versions
aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version 15.3 \
  --query 'DBEngineVersions[0].ValidUpgradeTarget[*].EngineVersion'

# 2. Upgrade (via Terraform)
# terraform/modules/rds/main.tf:
# engine_version = "15.4"
# auto_minor_version_upgrade = true

terraform apply

# RDS will apply during next maintenance window or immediately if specified
```

### Instance Patching

#### Security Patches (Monthly)

```bash
# 1. Update launch template with latest AMI
# terraform/modules/ec2/main.tf uses data source for latest Amazon Linux 2023 AMI

# 2. Apply Terraform (updates launch template)
cd terraform/environments/prod
terraform apply

# 3. Trigger rolling instance refresh
ASG_NAME=$(terraform output -raw asg_name)

aws autoscaling start-instance-refresh \
  --auto-scaling-group-name ${ASG_NAME} \
  --preferences '{
    "MinHealthyPercentage": 90,
    "InstanceWarmup": 300,
    "CheckpointPercentages": [50],
    "CheckpointDelay": 300
  }'

# 4. Monitor refresh
watch -n 30 "aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name ${ASG_NAME} \
  --max-records 1 \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]'"

# 5. Verify new instances
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ${ASG_NAME} \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LaunchTemplate.Version,HealthStatus]' \
  --output table
```

## Emergency Procedures

### Service Outage Response

**Immediate Actions** (within 5 minutes):

1. **Assess impact**:
   ```bash
   # Check if ALB is responding
   ALB_URL=$(cd terraform/environments/prod && terraform output -raw alb_url)
   curl -I -m 5 $ALB_URL/health

   # Check target health
   TG_ARN=$(cd terraform/environments/prod && terraform output -raw target_group_arn)
   aws elbv2 describe-target-health --target-group-arn ${TG_ARN}
   ```

2. **Determine scope**:
   - Total outage (no instances healthy)
   - Partial outage (some instances healthy)
   - Database outage (app healthy, DB down)
   - Network outage (can't reach AWS)

3. **Initiate incident response**:
   ```bash
   # Post to Slack/Teams
   # Update status page
   # Page on-call engineer if not already aware
   ```

### Emergency Scaling

**Manual Scale-Up** (immediate capacity increase):

```bash
# Increase desired capacity
ASG_NAME=$(cd terraform/environments/prod && terraform output -raw asg_name)

aws autoscaling set-desired-capacity \
  --auto-scaling-group-name ${ASG_NAME} \
  --desired-capacity 10 \
  --honor-cooldown

# Monitor new instances
watch -n 10 "aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ${ASG_NAME} \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]'"
```

### Emergency Rollback

**Immediate Rollback** (if deployment caused outage):

```bash
# Option 1: Cancel instance refresh (if in progress)
aws autoscaling cancel-instance-refresh \
  --auto-scaling-group-name ${ASG_NAME}

# Option 2: Revert Terraform state
cd terraform/environments/prod
git log --oneline -10  # Find last good commit
git revert <BAD_COMMIT_SHA>
git push origin main

# GitHub Actions will redeploy previous version

# Option 3: Manual intervention (if CI/CD unavailable)
terraform apply -var="app_version=<PREVIOUS_VERSION>"
```

### Database Emergency

**Database Failover** (Multi-AZ only):

```bash
# Force failover to standby
aws rds reboot-db-instance \
  --db-instance-identifier demo-flask-app-prod-db \
  --force-failover

# Monitor failover (typically 1-2 minutes)
watch -n 5 "aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-prod-db \
  --query 'DBInstances[0].[DBInstanceStatus,AvailabilityZone,SecondaryAvailabilityZone]'"
```

**Database Connection Storm** (too many connections):

```bash
# Option 1: Increase max_connections (requires reboot)
# See "Database Maintenance" section above

# Option 2: Kill idle connections (temporary relief)
# Connect to database and run:
# SELECT pg_terminate_backend(pid) FROM pg_stat_activity
#   WHERE state = 'idle' AND state_change < NOW() - INTERVAL '5 minutes';

# Option 3: Restart application instances to reset connection pools
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name ${ASG_NAME}
```

## Useful Commands

### Quick Reference

#### Infrastructure Status

```bash
# Get all infrastructure outputs
cd terraform/environments/prod
terraform output

# Get specific output
terraform output -raw alb_url
terraform output -raw db_endpoint
terraform output -raw cloudwatch_dashboard_url

# Check Terraform state
terraform state list
terraform state show aws_lb.main
```

#### Instance Management

```bash
# List all instances in ASG
ASG_NAME="demo-flask-app-prod-asg"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names ${ASG_NAME} \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,AvailabilityZone]' \
  --output table

# SSH into instance (via SSM)
INSTANCE_ID="i-0123456789abcdef0"
aws ssm start-session --target ${INSTANCE_ID}

# Run command on all instances
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:aws:autoscaling:groupName,Values=${ASG_NAME}" \
  --parameters 'commands=["uptime","free -h","df -h"]' \
  --output text

# Check command results
COMMAND_ID="<from previous command>"
aws ssm list-command-invocations --command-id ${COMMAND_ID}
```

#### Database Operations

```bash
# Connect to RDS
DB_ENDPOINT=$(cd terraform/environments/prod && terraform output -raw db_endpoint)
SECRET_ARN=$(cd terraform/environments/prod && terraform output -raw db_secret_arn)

# Get credentials
aws secretsmanager get-secret-value \
  --secret-id ${SECRET_ARN} \
  --query SecretString \
  --output text | jq -r '.password'

# Connect (from instance or local if security group allows)
psql -h ${DB_ENDPOINT} -U postgres -d demo_db

# List active connections
# SELECT * FROM pg_stat_activity WHERE state = 'active';

# Check database size
# SELECT pg_database_size('demo_db');
```

#### Logging and Monitoring

```bash
# Tail logs in real-time
aws logs tail /aws/ec2/demo-flask-app-prod --follow

# Search logs
aws logs filter-log-events \
  --log-group-name /aws/ec2/demo-flask-app-prod \
  --filter-pattern "ERROR" \
  --start-time $(($(date +%s) - 3600))000

# Get metric value
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=<ALB_FULL_NAME> \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --period 300 \
  --statistics Average
```

## Contacts and Escalation

### On-Call Rotation

| Day | Primary | Secondary | Manager |
|-----|---------|-----------|---------|
| Mon-Wed | Engineer A | Engineer B | Manager X |
| Thu-Fri | Engineer B | Engineer C | Manager X |
| Sat-Sun | Engineer C | Engineer A | Manager Y |

### Escalation Path

**Level 1 - On-Call Engineer** (initial response):
- PagerDuty/Opsgenie alert
- Expected response: 15 minutes
- Handles: P2, P3 incidents

**Level 2 - Senior Engineer** (complex issues):
- Escalate via: PagerDuty escalation policy
- Expected response: 30 minutes
- Handles: P1 incidents, unresolved P2 after 1 hour

**Level 3 - Engineering Manager** (critical/business impact):
- Escalate via: Phone call
- Expected response: Immediate
- Handles: P0 incidents, data breaches, security incidents

**Level 4 - VP Engineering** (executive escalation):
- Escalate via: Phone call
- Expected response: Immediate
- Handles: Extended outages (>4 hours), major incidents

### Contact Information

**Engineering Team**:
- On-Call Rotation: https://company.pagerduty.com/
- Slack Channel: #devops-alerts
- Email: devops-team@company.com

**AWS Support**:
- Business Support: https://console.aws.amazon.com/support/
- Phone: 1-866-243-6727
- Account TAM: tam@amazon.com (if applicable)

**Vendors**:
- Domain Registrar: support@registrar.com
- Monitoring: support@monitoring-vendor.com

---

**Document Version**: 1.0
**Last Updated**: 2024-01-15
**Review Frequency**: Quarterly after major incidents
**Owner**: DevOps Team
