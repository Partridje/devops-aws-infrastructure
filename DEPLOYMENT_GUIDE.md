# Deployment Guide

This guide will help you deploy and test the entire infrastructure.

## Prerequisites

Before you start, ensure you have:

- ✅ AWS Account with administrative access
- ✅ AWS CLI installed and configured
- ✅ Terraform installed (v1.5.0+, recommended 1.9+)
- ✅ Docker installed (for local app testing)
- ✅ Git repository (GitHub recommended for CI/CD)

## Estimated Time

- **Quick Test (Local Only)**: 10 minutes
- **Full AWS Deployment (Dev)**: 30-40 minutes
- **Full Stack (Dev + CI/CD)**: 60 minutes

## Estimated Costs

- **Dev Environment**: ~$84/month (~$2.80/day)
- **Testing Period**: If you deploy for 2-3 hours then destroy: **$0.35 - $0.50**

---

## Option 1: Quick Local Test (No AWS Costs)

Test the application locally with Docker before deploying to AWS.

### Step 1: Start Local Environment

```bash
cd app

# Start PostgreSQL and Flask app
docker-compose up -d

# Wait 10 seconds for services to start
sleep 10
```

### Step 2: Test Endpoints

```bash
# Test health endpoint
curl http://localhost:5001/health

# Expected output:
# {
#   "status": "healthy",
#   "database": "connected",
#   "timestamp": "2024-11-01T..."
# }

# Test database endpoint
curl http://localhost:5001/db

# Test API - list items
curl http://localhost:5001/api/items

# Test API - create item
curl -X POST http://localhost:5001/api/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Item", "description": "Testing before deployment"}'

# Test metrics endpoint
curl http://localhost:5001/metrics
```

### Step 3: View Logs

```bash
# Application logs
docker-compose logs app

# Database logs
docker-compose logs postgres
```

### Step 4: Access pgAdmin (Optional)

Open browser: http://localhost:5050
- Email: `admin@example.com`
- Password: `admin`

### Step 5: Cleanup

```bash
docker-compose down -v
```

**✅ If all endpoints work, your application is ready!**

---

## Option 2: AWS Deployment Test (Costs ~$0.50 for 2-3 hours)

Deploy to AWS and test the full infrastructure.

### Phase 1: AWS Account Setup (5 minutes)

#### Step 0: Create IAM User (if not done yet)

**⚠️ IMPORTANT**: If you haven't created an IAM user yet, follow **[docs/IAM_SETUP.md](docs/IAM_SETUP.md)** first.

**Quick option**: Create user with `AdministratorAccess` policy (5 minutes)

Once you have Access Key ID and Secret Access Key, continue below.

#### Step 1: Configure AWS CLI

```bash
# Configure AWS credentials
aws configure

# Enter your credentials:
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region: eu-north-1
# Default output format: json

# Verify configuration
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-username"
# }
```

#### Step 2: Set Up Terraform Backend

```bash
cd /Users/partridge/dev/devops-aws-infrastructure

# Make script executable
chmod +x scripts/setup-terraform-backend.sh

# Run backend setup (creates S3 bucket for state)
./scripts/setup-terraform-backend.sh

# This will create:
# - S3 bucket: terraform-state-demo-flask-app-<ACCOUNT_ID>
# - DynamoDB table: terraform-state-lock-demo-flask-app
```

**Note**: Save the bucket name and table name shown in the output!

#### Step 3: Configure Backend in Terraform

```bash
cd terraform/environments/dev

# Create backend.tf file with your bucket name
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket         = "terraform-state-demo-flask-app-YOUR_ACCOUNT_ID"
    key            = "dev/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-state-lock-demo-flask-app"
    encrypt        = true
  }
}
EOF

# Replace YOUR_ACCOUNT_ID with your actual account ID
# Get your account ID:
aws sts get-caller-identity --query Account --output text
```

### Phase 2: Configure Environment Variables (5 minutes)

#### Step 1: Create terraform.tfvars

```bash
cd terraform/environments/dev

# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

Edit these important values:

```hcl
# Required: Change these
project_name = "demo-flask-app"
environment  = "dev"

# IMPORTANT: Your email for CloudWatch alarms
alert_email = "your-email@example.com"

# IMPORTANT: Your IP address for security
# ⚠️ WARNING: Most ISPs use DYNAMIC IP - it changes daily!
# Get your current IP: curl ifconfig.me
#
# Options:
# 1. Testing only: allowed_cidr_blocks = ["0.0.0.0/0"]  # Allow all (INSECURE)
# 2. Your current IP: allowed_cidr_blocks = ["YOUR_IP/32"]  # Update when IP changes
# 3. Your ISP range: allowed_cidr_blocks = ["185.123.0.0/16"]  # Find via: whois $(curl -s ifconfig.me)
allowed_cidr_blocks = ["YOUR_IP/32"]  # e.g., ["203.0.113.45/32"] - Replace YOUR_IP!

# Optional: Customize instance types if needed
instance_type = "t3.micro"  # Keep this for cost savings

# Optional: Reduce costs further
min_size     = 1
max_size     = 2
desired_size = 1

# Database settings (default is fine for testing)
db_instance_class    = "db.t3.micro"
db_allocated_storage = 20
```

**Important**:
- Replace `your-email@example.com` with your real email
- Replace `YOUR_IP` with your actual IP address (get it with `curl ifconfig.me`)

### Phase 3: Deploy Infrastructure (15-20 minutes)

#### Step 1: Initialize Terraform

```bash
cd terraform/environments/dev

terraform init

# You should see:
# Terraform has been successfully initialized!
```

#### Step 2: Plan Deployment

```bash
terraform plan -out=tfplan

# Review the plan carefully
# You should see:
# Plan: 50+ to add, 0 to change, 0 to destroy
```

**Review**: Check that resources look correct (VPC, subnets, RDS, ALB, ASG, etc.)

#### Step 3: Apply Infrastructure

```bash
terraform apply tfplan

# This will take 15-20 minutes
# Watch the progress...
```

**What's being created:**
1. VPC with subnets across 2 AZs
2. Internet Gateway and NAT Gateway
3. Security Groups
4. RDS PostgreSQL database
5. Application Load Balancer
6. Auto Scaling Group with EC2 instances
7. CloudWatch monitoring
8. SNS topics for alerts

#### Step 4: Save Outputs

```bash
# After apply completes, save the outputs
terraform output > deployment-outputs.txt

# View key outputs
terraform output alb_url
terraform output db_endpoint
terraform output cloudwatch_dashboard_url
```

**Save these values** - you'll need them for testing!

### Phase 4: Test Deployment (10 minutes)

#### Step 1: Wait for Instances to Be Ready

```bash
# Get ALB URL
ALB_URL=$(terraform output -raw alb_url)

echo "ALB URL: $ALB_URL"

# Wait 3-5 minutes for:
# 1. EC2 instances to launch
# 2. User data script to complete
# 3. Application to start
# 4. Health checks to pass

# You can monitor instance status:
ASG_NAME=$(terraform output -raw asg_name)

watch -n 10 "aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
  --output table"

# Press Ctrl+C to stop watching
```

#### Step 2: Test Health Endpoint

```bash
ALB_URL=$(terraform output -raw alb_url)

# Test health
curl -f "$ALB_URL/health"

# Expected output:
# {
#   "status": "healthy",
#   "database": "connected",
#   "timestamp": "...",
#   "instance_id": "i-..."
# }
```

If you get an error:
- **502 Bad Gateway**: Instances still starting, wait 2-3 more minutes
- **Connection refused**: ALB still registering targets, wait 1-2 minutes
- **Timeout**: Check security groups (make sure your IP is allowed)

#### Step 3: Test All Endpoints

```bash
ALB_URL=$(terraform output -raw alb_url)

# Test database connectivity
curl "$ALB_URL/db"

# Test API - list items
curl "$ALB_URL/api/items"

# Test API - create item
curl -X POST "$ALB_URL/api/items" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test from AWS", "description": "Deployed successfully!"}'

# Test API - list items again (should see your new item)
curl "$ALB_URL/api/items"

# Test metrics
curl "$ALB_URL/metrics"
```

#### Step 4: Check CloudWatch Dashboard

```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url

# Copy and paste in browser
# You should see:
# - ALB metrics (request count, response time)
# - ASG metrics (instance count)
# - RDS metrics (CPU, connections)
```

#### Step 5: Check Email for SNS Subscription

1. Check your email inbox
2. Look for "AWS Notification - Subscription Confirmation"
3. Click "Confirm subscription"
4. This enables CloudWatch alarm notifications

#### Step 6: Test Auto Scaling (Optional)

```bash
# Generate load to trigger scaling
ALB_URL=$(terraform output -raw alb_url)

# Run this in a loop to generate load
for i in {1..100}; do
  curl -s "$ALB_URL/health" > /dev/null &
done

# Wait 5-10 minutes and check if new instances are launched
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw asg_name) \
  --query 'AutoScalingGroups[0].[DesiredCapacity,Instances[*].InstanceId]'
```

#### Step 7: View Application Logs

```bash
# Get log group name
LOG_GROUP="/aws/ec2/demo-flask-app-dev"

# Tail logs in real-time
aws logs tail $LOG_GROUP --follow

# Or view recent logs
aws logs tail $LOG_GROUP --since 10m

# Search for errors
aws logs filter-log-events \
  --log-group-name $LOG_GROUP \
  --filter-pattern "ERROR" \
  --start-time $(($(date +%s) - 3600))000
```

#### Step 8: Connect to Instance via SSM (Optional)

```bash
# Get instance ID
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw asg_name) \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

# Start SSM session (no SSH needed!)
aws ssm start-session --target $INSTANCE_ID

# Inside the instance:
# Check Docker containers
sudo docker ps

# Check application logs
sudo docker logs $(sudo docker ps -q)

# Check database connectivity
curl localhost:5001/health

# Exit
exit
```

### Phase 5: Cleanup (IMPORTANT - Avoid Charges!)

#### Step 1: Destroy Infrastructure

```bash
cd terraform/environments/dev

# Destroy all resources
terraform destroy

# Type 'yes' to confirm

# This will take 10-15 minutes
```

**What gets deleted:**
- All EC2 instances
- RDS database (with final snapshot)
- ALB and Target Groups
- Auto Scaling Group
- NAT Gateway
- All other resources

**What remains:**
- S3 bucket (Terraform state) - minimal cost (<$0.01/month)
- CloudWatch Logs - minimal cost
- Final RDS snapshot - can be deleted manually

#### Step 2: Verify Everything is Deleted

```bash
# Check for any remaining EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=demo-flask-app" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table

# Check for any remaining RDS instances
aws rds describe-db-instances \
  --query 'DBInstances[?TagList[?Key==`Project` && Value==`demo-flask-app`]].[DBInstanceIdentifier,DBInstanceStatus]' \
  --output table

# Check for any remaining Load Balancers
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Tags[?Key==`Project` && Value==`demo-flask-app`]].[LoadBalancerName,State.Code]' \
  --output table
```

If anything remains, delete manually through AWS Console.

#### Step 3: Delete RDS Snapshot (Optional)

```bash
# List final snapshots
aws rds describe-db-snapshots \
  --query 'DBSnapshots[?contains(DBSnapshotIdentifier, `demo-flask-app`)].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# Delete snapshot if you don't need it
aws rds delete-db-snapshot \
  --db-snapshot-identifier demo-flask-app-dev-db-final-snapshot-YYYY-MM-DD-hhmm
```

---

## Option 3: Full Stack Test with GitHub Actions (Optional)

If you want to test the complete CI/CD pipeline:

### Step 1: Push to GitHub

```bash
cd /Users/partridge/dev/devops-aws-infrastructure

# Initialize git (if not already)
git init
git add .
git commit -m "Initial commit: Production-ready DevOps infrastructure"

# Create repository on GitHub (via web interface)
# Then push:
git remote add origin https://github.com/YOUR_USERNAME/devops-aws-infrastructure.git
git branch -M main
git push -u origin main
```

### Step 2: Setup GitHub OIDC

```bash
# Run OIDC setup script
chmod +x scripts/setup-github-oidc.sh
./scripts/setup-github-oidc.sh

# Follow prompts to enter:
# - GitHub username
# - Repository name

# Note the role ARN shown at the end
```

### Step 3: Add GitHub Secrets

1. Go to: `https://github.com/YOUR_USERNAME/devops-aws-infrastructure/settings/secrets/actions`
2. Click "New repository secret"
3. Name: `AWS_ROLE_ARN`
4. Value: The ARN from previous step (e.g., `arn:aws:iam::123456789012:role/github-actions-role`)
5. Click "Add secret"

### Step 4: Test Workflows

```bash
# Make a change to trigger workflows
echo "# Testing CI/CD" >> README.md
git add README.md
git commit -m "Test: Trigger CI/CD workflows"
git push

# Go to GitHub Actions tab to see workflows running:
# https://github.com/YOUR_USERNAME/devops-aws-infrastructure/actions
```

**Workflows that will run:**
1. **Tests** - Validates Terraform, Python, Docker
2. **Terraform Plan** - Shows what would be deployed (on PR)
3. **Terraform Apply** - Deploys infrastructure (on merge to main)
4. **App Deploy** - Builds and deploys Docker image

---

## Troubleshooting Common Issues

### Issue 1: "Access Denied" Errors

**Problem**: AWS credentials don't have sufficient permissions

**Solution**:
```bash
# Verify your credentials
aws sts get-caller-identity

# Ensure you have AdministratorAccess policy or these permissions:
# - EC2: Full
# - RDS: Full
# - VPC: Full
# - IAM: Create/Attach roles
# - CloudWatch: Full
# - S3: Full (for Terraform state)
```

### Issue 2: "Cannot connect to ALB"

**Problem**: Security groups or health checks failing

**Solution**:
```bash
# Check target health
TG_ARN=$(terraform output -raw target_group_arn)
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# If unhealthy, check instance logs:
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw asg_name) \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

# View user data logs
aws ssm start-session --target $INSTANCE_ID
sudo cat /var/log/user-data.log
```

### Issue 3: "Database connection failed"

**Problem**: RDS not accessible or credentials wrong

**Solution**:
```bash
# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-dev-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]'

# Check security group rules
DB_SG=$(aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-dev-db \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

aws ec2 describe-security-groups --group-ids $DB_SG
```

### Issue 4: High AWS Costs

**Problem**: Resources left running after testing

**Solution**:
```bash
# Immediate cleanup
cd terraform/environments/dev
terraform destroy -auto-approve

# Double-check via AWS Cost Explorer:
# https://console.aws.amazon.com/cost-management/home#/dashboard

# Or via CLI:
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -d '1 day ago' +%Y-%m-%d),End=$(date -u +%Y-%m-%d) \
  --granularity DAILY \
  --metrics UnblendedCost \
  --group-by Type=SERVICE
```

---

## Pre-Deployment Checklist

Before deploying to production, ensure:

- [ ] Local Docker test passed ✅
- [ ] AWS deployment successful ✅
- [ ] All endpoints working ✅
- [ ] CloudWatch dashboard visible ✅
- [ ] Test infrastructure destroyed (no ongoing costs) ✅
- [ ] GitHub repository pushed ✅
- [ ] Documentation reviewed ✅
- [ ] All sensitive data removed (AWS keys, email addresses) ✅

---

## Cost Breakdown (for 2-3 hour test)

| Resource | Hourly Cost | 3-Hour Cost |
|----------|-------------|-------------|
| EC2 t3.micro (2 instances) | $0.0104 | $0.06 |
| NAT Gateway | $0.045 | $0.14 |
| RDS db.t3.micro | $0.017 | $0.05 |
| ALB | $0.0225 | $0.07 |
| Data Transfer | ~$0.01 | $0.03 |
| CloudWatch | ~$0.01 | $0.03 |
| **Total** | **~$0.14/hour** | **~$0.42** |

**To minimize costs:**
1. Test during off-hours
2. Destroy immediately after testing
3. Use `t3.micro` instances (included in free tier if available)

---

## Project Features

This repository includes:

1. **Professional Structure** - Clean, organized, production-ready
2. **Comprehensive Documentation** - README, ARCHITECTURE, SECURITY, RUNBOOK
3. **Complete IaC** - All Terraform modules properly structured
4. **Working Application** - Production-grade Flask app with all features
5. **CI/CD Pipeline** - Automated testing and deployment
6. **Security Best Practices** - Defense in depth, least privilege
7. **Operational Excellence** - Monitoring, logging, alerting

**Available commands:**
- `make validate` - Check Terraform configuration
- `make apply ENV=dev` - Deploy infrastructure
- `make app-run` - Test locally
- `make help` - See all available commands

---

## Key Technical Topics

Important areas to understand:

1. **Architecture Decisions**: Why 3-tier? Why Multi-AZ?
2. **Security**: Defense in depth implementation
3. **Scaling**: Auto-scaling configuration and policies
4. **Monitoring**: CloudWatch dashboards and alarms
5. **CI/CD**: GitHub Actions workflows
6. **Cost Optimization**: Dev vs Prod differences
7. **Disaster Recovery**: RDS backups and restore procedures
8. **Troubleshooting**: Production debugging procedures

---

## Support Commands

### Quick Status Check
```bash
# Check all resources
make status ENV=dev

# Health check
make health-check ENV=dev

# View logs
make logs ENV=dev

# Open dashboard
make dashboard ENV=dev
```

### Get Important URLs
```bash
cd terraform/environments/dev

# ALB URL (application endpoint)
terraform output alb_url

# CloudWatch Dashboard
terraform output cloudwatch_dashboard_url

# RDS Endpoint (for reference)
terraform output db_endpoint
```

---

**Good luck with your deployment! 🚀**

If you encounter any issues, refer to the RUNBOOK.md for troubleshooting procedures.
