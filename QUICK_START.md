# Quick Start Guide - 15 Minutes to Running Infrastructure

## What You'll Get

After 15 minutes:
- ✅ VPC with Multi-AZ networking
- ✅ Application Load Balancer
- ✅ Auto Scaling Group with EC2 instances
- ✅ RDS PostgreSQL database
- ✅ CloudWatch monitoring
- ✅ Working Flask application

**Cost**: ~$0.50 for 2-3 hours of testing

---

## Prerequisites Check (2 minutes)

```bash
# 1. Check AWS CLI
aws --version
# Need: aws-cli/2.x or higher

# 2. Check Terraform
terraform version
# Need: Terraform v1.5.0+ (recommended 1.9+)

# 3. Check Docker (for local testing)
docker --version
# Need: Docker version 20.x or higher

# 4. Configure AWS (need IAM user first!)
# ⚠️ If you don't have IAM user yet: see docs/IAM_SETUP.md
aws configure
# Enter your Access Key and Secret Key

# 5. Verify AWS access
aws sts get-caller-identity
# Should show your account ID and user ARN
```

**If any command fails, see DEPLOYMENT_GUIDE.md for installation instructions.**

**Don't have AWS credentials?** → **[docs/IAM_SETUP.md](docs/IAM_SETUP.md)** - Create IAM user in 5 minutes

---

## Step 1: Setup Terraform Backend (3 minutes)

```bash
# Navigate to project
cd /Users/partridge/dev/devops-aws-infrastructure

# Run backend setup (only needed ONCE)
chmod +x scripts/*.sh
./scripts/setup-terraform-backend.sh

# Script will automatically:
# - Use your AWS Account ID to create unique bucket name
# - Save configuration to .terraform-backend-config
# - Reuse same bucket if you run script again

# Example output:
# ✅ S3 bucket: terraform-state-demo-flask-app-123456789012
# ✅ DynamoDB table: terraform-state-lock-demo-flask-app
# ✅ Configuration saved to .terraform-backend-config
```

**Note**: Running this script multiple times is SAFE - it will reuse existing backend!

---

## Step 2: Configure Environment (3 minutes)

```bash
cd terraform/environments/dev

# Get your AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Your Account ID: $ACCOUNT_ID"

# Create backend configuration
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket         = "terraform-state-demo-flask-app-${ACCOUNT_ID}"
    key            = "dev/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-state-lock-demo-flask-app"
    encrypt        = true
  }
}
EOF

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Get your PUBLIC IP address (the one your ISP assigned to your router)
# ⚠️ WARNING: Most home/mobile ISPs use DYNAMIC IP - it can change daily!
MY_IP=$(curl -s ifconfig.me)
echo "Your public IP: $MY_IP"
echo ""
echo "⚠️  IMPORTANT: If your ISP uses dynamic IP, this will change!"
echo "   Solutions:"
echo "   1. Use 0.0.0.0/0 (allow all) for testing only"
echo "   2. Use VPN with static IP for production"
echo "   3. Update allowed_cidr_blocks when IP changes"
echo ""

# Edit terraform.tfvars - IMPORTANT!
cat > terraform.tfvars <<EOF
# Basic Configuration
project_name = "demo-flask-app"
environment  = "dev"
aws_region   = "eu-north-1"

# IMPORTANT: Change this to your email!
alert_email = "your-email@example.com"

# Security: Your IP for access
# ⚠️  Your ISP IP: ${MY_IP} (may change if dynamic!)
# Option 1 (TESTING ONLY): Allow all
# allowed_cidr_blocks = ["0.0.0.0/0"]
# Option 2 (RECOMMENDED): Your current public IP (update when it changes)
allowed_cidr_blocks = ["${MY_IP}/32"]
# Option 3: Your ISP's IP range (if known, e.g., "185.123.0.0/16")

# Cost savings
instance_type = "t3.micro"
min_size      = 1
max_size      = 2
desired_size  = 1

# Database
db_instance_class    = "db.t3.micro"
db_allocated_storage = 20
EOF

# NOW: Edit terraform.tfvars and change "your-email@example.com"
nano terraform.tfvars
# Change the email line, then press Ctrl+X, Y, Enter
```

---

## Step 3: Deploy Infrastructure (15 minutes)

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=tfplan

# Review the plan (should show ~50 resources to create)
# Press 'q' to quit viewing

# Apply (this takes 15-20 minutes)
terraform apply tfplan

# ☕ Take a coffee break!
```

**What's happening:**
1. Minutes 0-2: Creating VPC, subnets, gateways
2. Minutes 2-5: Creating security groups
3. Minutes 5-10: Creating RDS database
4. Minutes 10-15: Creating ALB and Auto Scaling Group
5. Minutes 15-20: EC2 instances starting and running health checks

---

## Step 4: Test Your Deployment (5 minutes)

```bash
# Get the application URL
ALB_URL=$(terraform output -raw alb_url)
echo "Your app is at: $ALB_URL"

# Wait for instances to be healthy (usually 3-5 minutes after terraform apply)
echo "Waiting for application to be ready..."
sleep 180  # Wait 3 minutes

# Test health endpoint
curl "$ALB_URL/health"

# Should return:
# {
#   "status": "healthy",
#   "database": "connected",
#   ...
# }
```

### If you get errors:

**502 Bad Gateway**: Wait 2 more minutes, instances still starting
```bash
sleep 120
curl "$ALB_URL/health"
```

**Connection timeout**: Your IP probably changed! (dynamic IP issue)
```bash
# Check your current IP
CURRENT_IP=$(curl -s ifconfig.me)
echo "Current IP: $CURRENT_IP"

# Check what IP is allowed in Security Group
terraform output alb_security_group_id

# Check if IP changed (compare with terraform.tfvars)
grep allowed_cidr_blocks terraform.tfvars

# If IP changed, update terraform.tfvars:
# Option A: Quick fix (allow all) - FOR TESTING ONLY!
sed -i '' 's/allowed_cidr_blocks = .*/allowed_cidr_blocks = ["0.0.0.0\/0"]/' terraform.tfvars

# Option B: Update to new IP (more secure)
sed -i '' "s/allowed_cidr_blocks = .*/allowed_cidr_blocks = [\"$CURRENT_IP\/32\"]/" terraform.tfvars

# Re-apply
terraform apply -auto-approve

# Test again
curl "$ALB_URL/health"
```

---

## Step 5: Test All Features (3 minutes)

```bash
ALB_URL=$(terraform output -raw alb_url)

# 1. Test database connectivity
curl "$ALB_URL/db"

# 2. List items (should be empty initially)
curl "$ALB_URL/api/items"

# 3. Create an item
curl -X POST "$ALB_URL/api/items" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Item", "description": "My first item!"}'

# 4. List items again (should see your item)
curl "$ALB_URL/api/items"

# 5. Check metrics
curl "$ALB_URL/metrics"
```

---

## Step 6: View CloudWatch Dashboard (2 minutes)

```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url

# Copy URL and paste in browser
# You should see:
# - Request count graph
# - Response time graph
# - Instance health
# - Database metrics
```

---

## Step 7: Cleanup (IMPORTANT!) (10 minutes)

```bash
# Destroy all resources
terraform destroy

# Type: yes

# Wait 10-15 minutes for everything to be deleted
```

**What gets deleted:**
- EC2 instances
- ALB
- RDS database (with final snapshot)
- NAT Gateway
- All networking

**What remains (minimal cost):**
- S3 bucket for Terraform state (<$0.01/month)
- CloudWatch logs (<$0.05/month)
- RDS final snapshot (can delete manually)

---

## Verification After Cleanup

```bash
# Check nothing is running
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=demo-flask-app" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table

# Should show: No instances

# Check your AWS bill (optional)
# https://console.aws.amazon.com/billing/home#/
```

---

## 🌐 Dynamic IP Problem & Solutions

### Problem: ISP Changes Your IP Daily

Most home internet providers use **dynamic IP addresses** - your public IP can change:
- Every 24 hours (DHCP lease renewal)
- When router reboots
- Randomly by ISP

**Symptom**: Infrastructure works today, but tomorrow you get "Connection timeout"

### Solution Options

#### Option 1: Allow All (Testing Only) ⚠️

```bash
# terraform.tfvars
allowed_cidr_blocks = ["0.0.0.0/0"]
```

**Pros**: Never breaks, works from anywhere
**Cons**: ❌ **INSECURE** - anyone in the world can access your ALB
**Use case**: Quick testing, demo, will destroy soon

#### Option 2: Update IP When Changed (Manual)

```bash
# Check current IP
curl ifconfig.me

# Update terraform.tfvars with new IP
allowed_cidr_blocks = ["NEW_IP/32"]

# Re-apply
terraform apply -auto-approve
```

**Pros**: Secure
**Cons**: ⚠️ Manual work every time IP changes
**Use case**: Dev environment, occasional testing

#### Option 3: Use Your ISP's IP Range

Some ISPs allocate IPs from specific ranges. Example: if your IPs are always 185.123.x.x:

```bash
# terraform.tfvars
allowed_cidr_blocks = ["185.123.0.0/16"]
```

**How to find your ISP range:**
```bash
# Get your IP
MY_IP=$(curl -s ifconfig.me)

# Look up the range (using whois)
whois $MY_IP | grep -i "CIDR\|route"
```

**Pros**: Secure, works even when IP changes within range
**Cons**: Allows others on same ISP in your city
**Use case**: Long-running dev environment

#### Option 4: Use VPN with Static IP (Best for Production)

Services like:
- AWS Client VPN (expensive ~$30/month)
- Tailscale (free for personal)
- ZeroTier (free for personal)
- Commercial VPN with static IP ($5-10/month)

```bash
# Connect to VPN
# VPN gives you static IP: 45.67.89.10

# terraform.tfvars
allowed_cidr_blocks = ["45.67.89.10/32"]
```

**Pros**: ✅ Secure, ✅ Never changes, ✅ Works from anywhere
**Cons**: Additional cost, need to connect VPN
**Use case**: Production, team environment

#### Option 5: Use AWS SSM Session Manager (No Public Access)

Remove ALB public access completely, use AWS Systems Manager:

```bash
# No allowed_cidr_blocks needed!
# Access via SSM tunnel
aws ssm start-session --target i-1234567890abcdef0

# Port forward
aws ssm start-session \
  --target i-1234567890abcdef0 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5000"],"localPortNumber":["8080"]}'

# Access on localhost
curl http://localhost:8080/health
```

**Pros**: ✅ Most secure, ✅ No public internet exposure
**Cons**: More complex setup
**Use case**: Production, high security requirements

### Recommended Approach

```
For this Quick Start tutorial:
  → Option 1 (allow 0.0.0.0/0) ✅
  → Deploy, test for 2-3 hours, then terraform destroy
  → Total risk: minimal (will be destroyed soon)

For real dev environment:
  → Option 2 or 3 (your IP or ISP range)
  → Update when IP changes

For production:
  → Option 4 (VPN) or Option 5 (SSM)
```

---

## Troubleshooting Quick Fixes

### Can't connect to application

```bash
# Check instance health
ASG_NAME=$(terraform output -raw asg_name)
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
  --output table

# If unhealthy, check logs
aws logs tail /aws/ec2/demo-flask-app-dev --since 10m
```

### Database connection failed

```bash
# Check RDS status
terraform output db_endpoint

aws rds describe-db-instances \
  --db-instance-identifier demo-flask-app-dev-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]'

# Should show: "available"
```

### Terraform errors

```bash
# Re-initialize
terraform init -upgrade

# Validate
terraform validate

# If state issues
terraform state list
```

---

## Makefile Shortcuts

The project includes a Makefile with convenient commands:

```bash
# Validate Terraform
make validate ENV=dev

# Plan changes
make plan ENV=dev

# Apply infrastructure
make apply ENV=dev

# Destroy everything
make destroy ENV=dev

# Check health
make health-check ENV=dev

# View logs
make logs ENV=dev

# SSH into instance (via SSM)
make ssh ENV=dev

# See all commands
make help
```

---

## Time-Based Checklist

**If you have 30 minutes:**
- ✅ Local Docker test (10 min)
- ✅ Review documentation (10 min)
- ✅ Test Terraform validation (10 min)

**If you have 1 hour:**
- ✅ Local Docker test (10 min)
- ✅ AWS deployment (20 min)
- ✅ Testing (10 min)
- ✅ Cleanup (10 min)
- ✅ Review (10 min)

**If you have 2 hours:**
- ✅ Everything above
- ✅ Setup GitHub repository
- ✅ Configure CI/CD
- ✅ Test workflows
- ✅ Prepare demo

---

## Cost Calculator

**Dev Environment (what you'll deploy):**
- 2x t3.micro EC2: $0.0104/hour × 2 = $0.021/hour
- 1x NAT Gateway: $0.045/hour
- 1x db.t3.micro RDS: $0.017/hour
- 1x ALB: $0.0225/hour
- Other: ~$0.02/hour

**Total: ~$0.14/hour or $0.42 for 3 hours**

**If you keep it running for 24 hours: ~$3.36**
**Monthly: ~$100**

⚠️ **IMPORTANT: Run `terraform destroy` after testing!**

---

## Support Resources

- **Full Deployment Guide**: DEPLOYMENT_GUIDE.md
- **Architecture Details**: docs/ARCHITECTURE.md
- **Security Info**: docs/SECURITY.md
- **Operations**: docs/RUNBOOK.md
- **Troubleshooting**: docs/RUNBOOK.md (Troubleshooting section)

---

## Ready to Deploy?

```bash
# Quick sanity check
cd /Users/partridge/dev/devops-aws-infrastructure
aws sts get-caller-identity  # ✅ AWS configured?
terraform version            # ✅ Terraform installed?

# If both pass, you're ready!
# Start with Step 1 above ⬆️
```

**Good luck! 🚀**
