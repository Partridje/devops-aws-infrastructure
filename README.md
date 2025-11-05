# Production-Ready AWS Infrastructure with Terraform

[![Terraform](https://img.shields.io/badge/Terraform-1.9+-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![Python](https://img.shields.io/badge/Python-3.11+-3776AB?logo=python)](https://www.python.org/)

A production-ready, highly available, and secure AWS infrastructure deployment using Infrastructure as Code (Terraform) with a demo Flask application.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                               AWS Cloud (eu-north-1)                            │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                         VPC (10.0.0.0/16)                                  │ │
│  │                                                                            │ │
│  │  ┌──────────────────────────────────────────────────────────────────────┐  │ │
│  │  │                         Public Subnets                               │  │ │
│  │  │                                                                      │  │ │
│  │  │   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐          │  │ │  
│  │  │   │     NAT     │      │     NAT     │      │     NAT     │          │  │ │
│  │  │   │   Gateway   │      │   Gateway   │      │   Gateway   │          │  │ │
│  │  │   │   (AZ-1)    │      │   (AZ-2)    │      │   (AZ-3)    │          │  │ │
│  │  │   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘          │  │ │
│  │  │          │                     │                     │               │  │ │
│  │  │   ┌──────┴────────────────────┴─────────────────────┴──────┐         │  │ │
│  │  │   │          Application Load Balancer (ALB)               │         │  │ │
│  │  │   │          [HTTPS/HTTP] + WAF Protection                 │         │  │ │
│  │  │   └──────┬────────────────────┬─────────────────────┬──────┘         │  │ │
│  │  └──────────┼────────────────────┼─────────────────────┼────────────────┘  │ │
│  │             │                    │                     │                   │ │
│  │  ┌──────────┼────────────────────┼─────────────────────┼────────────────┐  │ │
│  │  │          │     Private Subnets (Application Tier)   │                │  │ │
│  │  │          │                    │                     │                │  │ │
│  │  │   ┌──────▼──────┐      ┌──────▼──────┐      ┌──────▼──────┐          │  │ │
│  │  │   │   EC2 Auto  │      │   EC2 Auto  │      │   EC2 Auto  │          │  │ │
│  │  │   │   Scaling   │      │   Scaling   │      │   Scaling   │          │  │ │
│  │  │   │   (AZ-1)    │      │   (AZ-2)    │      │   (AZ-3)    │          │  │ │
│  │  │   │  [Docker]   │      │  [Docker]   │      │  [Docker]   │          │  │ │
│  │  │   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘          │  │ │
│  │  │          └────────────────────┴────────────────────┘                 │  │ │
│  │  └──────────────────────────────────┬───────────────────────────────────┘  │
│  │                                      │                                     │ │
│  │  ┌───────────────────────────────────┼──────────────────────────────────┐  │ │
│  │  │           Private Subnets (Database Tier)                            │  │ │
│  │  │                                   │                                  │  │ │
│  │  │                     ┌─────────────▼──────────────┐                   │  │ │
│  │  │                     │   RDS PostgreSQL (Primary) │                   │  │ │
│  │  │                     │   [Multi-AZ, Encrypted]    │                   │  │ │
│  │  │                     │   ┌──────────────────────┐ │                   │  │ │
│  │  │                     │   │  Standby (Auto-sync) │ │                   │  │ │
│  │  │                     │   └──────────────────────┘ │                   │  │ │
│  │  │                     └────────────────────────────┘                   │  │ │
│  │  └──────────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                  │
│  │  Secrets Manager│  │   CloudWatch    │  │   ECR Registry  │                  │
│  │  [Credentials]  │  │   [Monitoring]  │  │   [Images]      │                  │
│  └────────▲────────┘  └────────▲────────┘  └────────▲────────┘                  │
│           │                    │                     │                          │
│           └────────────────────┴─────────────────────┘                          │
│                          ▲ ▲ ▲                                                  │
│                          │ │ │                                                  │
└──────────────────────────┼─┼─┼──────────────────────────────────────────────────┘
                           │ │ │
                    ┌──────┘ │ └──────┐
                    │        │        │
            ┌───────▼────────▼────────▼───────┐
            │      Internet Gateway           │
            └───────┬─────────────────────────┘
                    │
            ════════▼════════
               Internet
                (Users)
            ════════════════

Legend:
  ┌─┐  Infrastructure boundary
  ──▶  Traffic flow
  ═══  External connection
  [  ] Component detail


## 🎯 Features

### Infrastructure
- **High Availability**: Multi-AZ deployment across 3 availability zones
- **Scalability**: Auto Scaling Group with CPU-based scaling policies
- **Security**: Network isolation, security groups, encrypted storage, secrets management
- **Monitoring**: CloudWatch dashboards, alarms, and structured logging
- **Disaster Recovery**: Automated backups, Multi-AZ RDS, infrastructure as code

### Application
- **Demo Flask API** with database integration
- **Health checks** and readiness probes
- **Prometheus metrics** endpoint
- **Graceful shutdown** handling
- **Structured JSON logging** for CloudWatch

### DevOps
- **GitOps workflow** with GitHub Actions
- **Automated CI/CD** pipeline
- **Infrastructure testing** with terraform validate, tflint
- **Security scanning** with Trivy
- **Cost estimation** with Infracost (optional)
- **OIDC authentication** (no static AWS credentials)

## 📋 Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads.html) >= 1.13.3 (required for state compatibility)
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- [Docker](https://www.docker.com/get-started) >= 20.10 (with buildx for multi-platform builds)
- [Python](https://www.python.org/downloads/) >= 3.11
- [Make](https://www.gnu.org/software/make/) (optional, for convenience)

### AWS Account Setup
1. **AWS Account** with appropriate permissions
2. **IAM User Setup**: See **[docs/IAM_SETUP.md](docs/IAM_SETUP.md)** for detailed instructions
3. **AWS CLI configured** with credentials:
   ```bash
   aws configure
   ```
4. **Required AWS permissions**:
   - VPC, EC2, RDS, ALB, Auto Scaling
   - IAM, Secrets Manager, KMS
   - CloudWatch, S3, DynamoDB
   - Systems Manager

### Terraform Backend Setup
Before deploying, create S3 bucket and DynamoDB table for remote state:

```bash
# Run the backend setup script
cd scripts
./setup-terraform-backend.sh <your-aws-region> <unique-bucket-name>
```

Or manually:
```bash
aws s3api create-bucket \
  --bucket my-terraform-state-bucket \
  --region eu-north-1

aws s3api put-bucket-versioning \
  --bucket my-terraform-state-bucket \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket my-terraform-state-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-north-1
```

## 🚀 Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <your-repo-url>
cd devops-aws-infrastructure

# Copy example variables
cp terraform/environments/dev/terraform.tfvars.example \
   terraform/environments/dev/terraform.tfvars

# Edit variables with your values
vim terraform/environments/dev/terraform.tfvars
```

### 2. Initialize Terraform

```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Review the plan
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Apply the infrastructure
terraform apply

# Note the outputs (ALB DNS name, etc.)
terraform output
```

### 4. Access the Application

```bash
# Get the ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name)

# Test the application
curl http://${ALB_DNS}/
curl http://${ALB_DNS}/health
curl http://${ALB_DNS}/db
curl http://${ALB_DNS}/api/items
```

### 5. Using Makefile (Alternative)

```bash
# Initialize and plan
make init ENV=dev
make plan ENV=dev

# Deploy
make apply ENV=dev

# Destroy infrastructure
make destroy ENV=dev

# Cleanup backend (S3 + DynamoDB) - only when removing project completely
./scripts/cleanup-terraform-backend.sh
```

**Note**: `terraform destroy` removes all application infrastructure but **keeps** the Terraform backend (S3 buckets and DynamoDB table). This is intentional to preserve state history. Use `cleanup-terraform-backend.sh` only when completely removing the project.

## 📁 Project Structure

```
.
├── .github/
│   └── workflows/          # GitHub Actions CI/CD pipelines
│       ├── terraform-plan.yml
│       ├── terraform-apply.yml
│       └── app-deploy.yml
├── app/                    # Flask demo application
│   ├── src/
│   │   └── app.py
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── requirements.txt
│   └── README.md
├── terraform/
│   ├── modules/            # Reusable Terraform modules
│   │   ├── vpc/           # VPC, subnets, NAT, IGW
│   │   ├── security/      # Security groups
│   │   ├── ec2/           # ALB, ASG, Launch Template
│   │   ├── rds/           # PostgreSQL RDS
│   │   └── monitoring/    # CloudWatch dashboards, alarms
│   └── environments/       # Environment-specific configs
│       ├── dev/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── backend.tf
│       │   └── terraform.tfvars.example
│       └── prod/
├── scripts/                # Helper scripts
│   ├── setup-terraform-backend.sh
│   └── generate-cert.sh
├── docs/                   # Documentation
│   ├── ARCHITECTURE.md
│   ├── SECURITY.md
│   └── RUNBOOK.md
├── Makefile               # Convenience commands
├── .pre-commit-config.yaml # Pre-commit hooks
└── README.md
```

## 🔐 Security Features

### Network Security
- **Private subnets** for application and database tiers
- **Security groups** with least privilege principle
- **Network ACLs** for additional layer of defense
- **VPC Flow Logs** for network traffic analysis
- **NAT Gateways** for outbound internet access from private subnets
- **AWS WAF** protection against OWASP Top 10, DDoS, and malicious IPs (production)

### Data Security
- **Encryption at rest** for EBS volumes and RDS
- **Encryption in transit** with TLS/SSL on ALB (HTTPS with ACM certificates)
- **AWS Secrets Manager** for database credentials with rotation support
- **KMS** for encryption key management
- **No hardcoded credentials** in code or configuration

### Access Security
- **IAM roles** instead of access keys
- **SSM Session Manager** for instance access (no SSH keys)
- **IMDSv2** enforcement on EC2 instances
- **CloudTrail** for audit logging
- **MFA recommended** for AWS account access

### Application Security
- **Container image scanning** with Trivy
- **Security updates** in base images
- **Non-root container** user
- **Read-only root filesystem** where possible

See [SECURITY.md](docs/SECURITY.md) for detailed security practices.

## 📊 Monitoring & Observability

### CloudWatch Dashboards
- **Infrastructure metrics**: CPU, memory, disk, network
- **Application metrics**: Request rate, latency, errors
- **Database metrics**: Connections, IOPS, CPU, storage

### CloudWatch Alarms
- High CPU utilization (EC2 and RDS)
- Unhealthy targets in ALB
- High error rate (5xx responses)
- RDS storage threshold
- Low ALB healthy host count

### Logging
- **Application logs** in JSON format
- **VPC Flow Logs** for network analysis
- **CloudTrail** for API activity
- **ALB access logs** (optional, S3)

### Alerting
- **SNS topics** for alarm notifications
- **Email subscriptions** for critical alerts
- **Integration ready** for PagerDuty, Slack, etc.

## 💰 Cost Estimation

Estimated monthly cost for **dev environment** (eu-north-1):

| Service | Configuration | Est. Monthly Cost |
|---------|--------------|-------------------|
| EC2 (t3.small x2) | On-Demand | ~$30 |
| RDS (db.t3.micro) | Multi-AZ | ~$30 |
| ALB | Low traffic | ~$20 |
| NAT Gateway (x3) | Minimal data | ~$100 |
| EBS Volumes | 30 GB gp3 x2 | ~$5 |
| CloudWatch | Logs + Metrics | ~$10 |
| Secrets Manager | 2 secrets | ~$1 |
| **Total** | | **~$196/month** |

**Production environment** with larger instances and higher traffic: **~$400-800/month**

💡 **Cost Optimization Tips**:
- Use single NAT Gateway for dev (not HA)
- Enable RDS auto-scaling
- Use Savings Plans or Reserved Instances
- Implement S3 lifecycle policies
- Review CloudWatch log retention

## 🔧 Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `aws_region` | AWS region to deploy | `eu-north-1` |
| `environment` | Environment name | `dev` or `prod` |
| `project_name` | Project identifier | `myapp` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `azs_count` | Number of AZs | `3` |
| `ec2_instance_type` | EC2 instance type | `t3.small` |
| `asg_min_size` | ASG minimum size | `2` |
| `asg_desired_size` | ASG desired size | `2` |
| `asg_max_size` | ASG maximum size | `4` |
| `rds_instance_class` | RDS instance class | `db.t3.small` |
| `rds_multi_az` | RDS Multi-AZ | `true` |
| `db_name` | Database name | `appdb` |
| `enable_deletion_protection` | Prevent accidental deletion | `false` (dev) |

See `terraform/environments/*/terraform.tfvars.example` for complete list.

## 🧪 Testing

### Local Application Testing

```bash
cd app

# Run with Docker Compose
docker-compose up -d

# Test endpoints
curl http://localhost:5001/
curl http://localhost:5001/health
curl http://localhost:5001/api/items
curl -X POST http://localhost:5001/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"test","value":"123"}'

# View logs
docker-compose logs -f app

# Cleanup
docker-compose down
```

### Infrastructure Testing

```bash
# Terraform validation
terraform fmt -check -recursive
terraform validate

# TFLint
tflint --recursive

# Terraform plan
terraform plan

# tfsec security scanning
tfsec terraform/

# Checkov policy scanning
checkov -d terraform/
```

## 🔄 CI/CD Pipeline

### Workflows

1. **terraform-plan.yml** (Pull Requests)
   - Runs on PR to main
   - Validates Terraform code
   - Posts plan as PR comment
   - Estimates costs with Infracost

2. **terraform-apply.yml** (Main branch)
   - Runs on push to main
   - Applies infrastructure changes
   - Updates documentation

3. **app-deploy.yml** (Application changes)
   - Builds Docker image
   - Scans for vulnerabilities
   - Pushes to ECR
   - Deploys to EC2 instances
   - Runs smoke tests

### GitHub OIDC Setup

Configure GitHub Actions to authenticate with AWS using OIDC:

```bash
# Run the OIDC setup script
cd scripts
./setup-github-oidc.sh <github-org> <github-repo>
```

Add these secrets to GitHub repository:
- `AWS_REGION`: Your AWS region
- `AWS_ACCOUNT_ID`: Your AWS account ID
- `TERRAFORM_ROLE_ARN`: ARN of the Terraform execution role

## 📚 Documentation

### Quick Start
- **[QUICK_START.md](QUICK_START.md)** - Deploy in 15 minutes (recommended for first-time users)
- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Comprehensive deployment guide with all options

### Understanding the System
- **[HOW_IT_WORKS.md](HOW_IT_WORKS.md)** - Complete system explanation with diagrams
- **[FILES_OVERVIEW.md](FILES_OVERVIEW.md)** - Guide to all files in the repository
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Detailed architecture decisions and patterns

### Operations & Security
- **[docs/IAM_SETUP.md](docs/IAM_SETUP.md)** - IAM user setup and permissions (START HERE)
- **[docs/RUNBOOK.md](docs/RUNBOOK.md)** - Operational procedures, troubleshooting, incident response
- **[docs/SECURITY.md](docs/SECURITY.md)** - Security best practices, compliance, and hardening
- **[docs/PASSWORD_MANAGEMENT.md](docs/PASSWORD_MANAGEMENT.md)** - AWS managed passwords (ephemeral approach)
- **[docs/SECRETS_ACCESS_CONTROL.md](docs/SECRETS_ACCESS_CONTROL.md)** - IAM policies, access control, monitoring

### Configuration & Setup
- **[docs/HTTPS_SETUP.md](docs/HTTPS_SETUP.md)** - SSL/TLS certificates and HTTPS configuration
- **[docs/SNS_SETUP.md](docs/SNS_SETUP.md)** - Email alerts and notification configuration
- **[docs/WAF_SETUP.md](docs/WAF_SETUP.md)** - Web Application Firewall configuration
- **[docs/SECRETS_ROTATION.md](docs/SECRETS_ROTATION.md)** - RDS password rotation procedures
- **[docs/SESSION_MANAGER.md](docs/SESSION_MANAGER.md)** - Secure EC2 access without SSH
- **[docs/DEPENDABOT.md](docs/DEPENDABOT.md)** - Automatic dependency updates with Dependabot

### Component Documentation
- **[app/README.md](app/README.md)** - Flask application documentation
- **[app/DOCKER.md](app/DOCKER.md)** - Docker setup and usage
- **[terraform/modules/*/README.md](terraform/modules/)** - Individual Terraform module documentation
- **[scripts/README.md](scripts/README.md)** - Helper scripts documentation

## ⚠️ Critical Fixes & Known Issues

### Resolved Issues

The following critical issues were identified and fixed during development:

1. **IAM Permissions for RDS Secrets** ✅
   - **Problem**: EC2 instances couldn't access AWS-managed RDS master password secret
   - **Solution**: Added `db_master_secret_arn` and `rds_kms_key_arn` to EC2 IAM role policy
   - **Location**: `terraform/modules/ec2/main.tf` lines 124-153

2. **Docker Platform Mismatch** ✅
   - **Problem**: Images built on arm64 (Mac M1) failed on amd64 EC2 instances
   - **Solution**: Always build with `--platform linux/amd64`
   - **Command**: `docker buildx build --platform linux/amd64 -t app:latest . --load`

3. **Package Conflicts on Amazon Linux 2023** ✅
   - **Problem**: `dnf update -y` caused curl-minimal conflicts
   - **Solution**: Removed system update from user_data.sh
   - **Location**: `terraform/modules/ec2/user_data.sh`

4. **RDS Static Parameters** ✅
   - **Problem**: Cannot use `apply_method = "immediate"` for static parameters
   - **Solution**: Changed to `apply_method = "pending-reboot"`
   - **Location**: `terraform/modules/rds/main.tf`

5. **Volume Size Requirements** ✅
   - **Problem**: Amazon Linux 2023 AMI requires minimum 30GB root volume
   - **Solution**: Increased `root_volume_size` from 20GB to 30GB
   - **Location**: `terraform/environments/*/main.tf`

6. **Terraform Version Compatibility** ✅
   - **Problem**: CI used v1.5.0 while local used v1.13.3, causing state errors
   - **Solution**: Synchronized version to 1.13.3 across all workflows
   - **Location**: `.github/workflows/*.yml`

## 🐛 Troubleshooting

### Terraform Issues

**Issue**: State lock error
```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>
```

**Issue**: Resource already exists
```bash
# Import existing resource
terraform import <resource_type>.<name> <resource_id>
```

### Application Issues

**Issue**: Cannot connect to database
```bash
# Check security groups allow traffic
# Verify RDS is in available state
# Check secrets in Secrets Manager
aws secretsmanager get-secret-value --secret-id <secret-name>
```

**Issue**: 502 Bad Gateway from ALB
```bash
# Check target health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# Check application logs in CloudWatch
aws logs tail /aws/ec2/application --follow
```

### Access Issues

**Issue**: Cannot SSH to instances
```bash
# Use SSM Session Manager instead
aws ssm start-session --target <instance-id>
```

## 🧹 Cleanup

### Destroy Infrastructure

```bash
# Using Terraform
cd terraform/environments/dev
terraform destroy

# Using Makefile
make destroy ENV=dev

# Cleanup state bucket (optional, after all environments destroyed)
aws s3 rb s3://<bucket-name> --force
aws dynamodb delete-table --table-name terraform-state-lock
```

### Important Notes
- RDS deletion protection must be disabled first if enabled
- S3 buckets must be empty before deletion
- Some resources may have termination protection

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Workflow
1. Install pre-commit hooks: `pre-commit install`
2. Make changes
3. Run tests: `make test`
4. Create PR

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [Terraform AWS Modules](https://github.com/terraform-aws-modules)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [12-Factor App](https://12factor.net/)

## 📞 Support

For issues, questions, or contributions, please open an issue in the GitHub repository.

---

**Note**: This infrastructure is designed for demonstration and learning purposes. For production use, additional considerations may be required based on your specific requirements and compliance needs.
