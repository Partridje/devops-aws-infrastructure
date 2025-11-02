# Project Files Overview

Complete reference of all files in the project and what they do.

## Quick Navigation

**Start Here**:
- `README_FOR_TESTING.md` ← **START HERE** before testing!
- `HOW_IT_WORKS.md` ← Understand how everything works
- `QUICK_START.md` ← 15-minute deployment guide

**Main Documentation**:
- `README.md` - Project overview
- `DEPLOYMENT_GUIDE.md` - Complete deployment instructions
- `FINAL_REVIEW.md` - Stage 12 completion summary

**Technical Docs**:
- `docs/ARCHITECTURE.md` - System architecture (400+ lines)
- `docs/SECURITY.md` - Security documentation (1100+ lines)
- `docs/RUNBOOK.md` - Operations procedures (1200+ lines)

---

## Root Directory Files

| File | Purpose | When to Use |
|------|---------|-------------|
| `README.md` | Main project documentation | First thing to read |
| `README_FOR_TESTING.md` | Testing guide with 3 options | Before you start testing |
| `HOW_IT_WORKS.md` | Explains system internals | To understand architecture |
| `QUICK_START.md` | 15-min quick deployment | Fast AWS deployment |
| `DEPLOYMENT_GUIDE.md` | Comprehensive deployment | Full deployment walkthrough |
| `FINAL_REVIEW.md` | Stage 12 completion summary | See what was fixed in final stage |
| `FILES_OVERVIEW.md` | This file | Find any file quickly |
| `Makefile` | Convenience commands | Run `make help` |
| `.gitignore` | Git ignore rules | Automatic |
| `.pre-commit-config.yaml` | Pre-commit hooks | For development |
| `.tflint.hcl` | Terraform linting config | Terraform validation |
| `.markdownlint.json` | Markdown linting config | Documentation quality |

---

## Application Files (`app/`)

### Main Application
| File | Purpose | Lines |
|------|---------|-------|
| `src/app.py` | Flask application | 500+ |
| `requirements.txt` | Python dependencies | 20 |
| `.env.example` | Environment variables template | 30 |

### Docker Configuration
| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage Docker build |
| `docker-compose.yml` | Local development environment |
| `init.sql` | PostgreSQL initialization |
| `.dockerignore` | Docker build exclusions |

### Documentation
| File | Purpose |
|------|---------|
| `README.md` | Application documentation |
| `DOCKER.md` | Docker usage guide |

---

## Terraform Infrastructure (`terraform/`)

### Modules

#### VPC Module (`terraform/modules/vpc/`)
| File | Purpose | Resources Created |
|------|---------|-------------------|
| `main.tf` | VPC infrastructure | VPC, Subnets, IGW, NAT, Routes |
| `variables.tf` | Input variables | N/A |
| `outputs.tf` | Output values | N/A |
| `versions.tf` | Provider versions | N/A |
| `README.md` | Module documentation | N/A |

**Creates**: VPC, 6 subnets (public/private/database), Internet Gateway, NAT Gateway, Route Tables, VPC Flow Logs

#### Security Module (`terraform/modules/security/`)
| File | Purpose | Resources Created |
|------|---------|-------------------|
| `main.tf` | Security groups | ALB SG, App SG, RDS SG, VPC Endpoint SG |
| `variables.tf` | Input variables | N/A |
| `outputs.tf` | Output values | N/A |
| `versions.tf` | Provider versions | N/A |
| `README.md` | Module documentation | N/A |

**Creates**: 4 security groups with referenced security group rules

#### RDS Module (`terraform/modules/rds/`)
| File | Purpose | Resources Created |
|------|---------|-------------------|
| `main.tf` | PostgreSQL database | RDS instance, Secrets Manager, KMS key, Parameter Group, CloudWatch Alarms |
| `variables.tf` | Input variables | N/A |
| `outputs.tf` | Output values | N/A |
| `versions.tf` | Provider versions | N/A |
| `README.md` | Module documentation | N/A |

**Creates**: RDS PostgreSQL (Multi-AZ), Secrets Manager secret, KMS key, Parameter/Option Groups, 4 CloudWatch alarms

#### EC2 Module (`terraform/modules/ec2/`)
| File | Purpose | Resources Created |
|------|---------|-------------------|
| `main.tf` | Compute resources | ALB, Target Group, Launch Template, ASG, IAM roles, CloudWatch alarms |
| `user_data.sh` | Instance bootstrap script (600+ lines) | N/A |
| `variables.tf` | Input variables | N/A |
| `outputs.tf` | Output values | N/A |
| `versions.tf` | Provider versions | N/A |
| `README.md` | Module documentation | N/A |

**Creates**: ALB, Target Group, Launch Template, Auto Scaling Group, IAM roles, Scaling Policies, CloudWatch alarms

#### Monitoring Module (`terraform/modules/monitoring/`)
| File | Purpose | Resources Created |
|------|---------|-------------------|
| `main.tf` | CloudWatch monitoring | SNS Topic, CloudWatch Dashboard, Log Metric Filters, Alarms |
| `variables.tf` | Input variables | N/A |
| `outputs.tf` | Output values | N/A |
| `versions.tf` | Provider versions | N/A |
| `README.md` | Module documentation | N/A |

**Creates**: SNS topic, CloudWatch Dashboard, Log Metric Filters, CloudWatch Alarms, EventBridge Rules

### Environments

#### Dev Environment (`terraform/environments/dev/`)
| File | Purpose |
|------|---------|
| `main.tf` | Dev configuration (2 AZs, t3.micro, single NAT) |
| `variables.tf` | Variable definitions |
| `outputs.tf` | Output values |
| `terraform.tfvars.example` | Example configuration |
| `backend.tf` | S3 backend configuration (created during setup) |

**Configuration**: Cost-optimized (2 AZs, 1 NAT, single-AZ RDS, t3.micro) - ~$84/month

#### Prod Environment (`terraform/environments/prod/`)
| File | Purpose |
|------|---------|
| `main.tf` | Prod configuration (3 AZs, t3.small, 3 NATs) |
| `variables.tf` | Variable definitions |
| `outputs.tf` | Output values |
| `terraform.tfvars.example` | Example configuration |
| `backend.tf` | S3 backend configuration (created during setup) |

**Configuration**: Production-ready (3 AZs, 3 NATs, Multi-AZ RDS, t3.small) - ~$275/month

---

## CI/CD Workflows (`.github/workflows/`)

| File | Triggers | Purpose |
|------|----------|---------|
| `tests.yml` | Every PR, every push | Run tests (Terraform, Python, Docker, Security) |
| `terraform-plan.yml` | PRs to main | Show Terraform plan, run validation |
| `terraform-apply.yml` | Push to main, manual | Deploy infrastructure |
| `app-deploy.yml` | Changes to `app/`, manual | Build and deploy application |

**Key Features**:
- Automated testing on every PR
- Security scanning (Trivy, Checkov, tfsec)
- Auto-deploy dev on merge to main
- Manual prod deployment with approval

---

## Scripts (`scripts/`)

| Script | Purpose | When to Run |
|--------|---------|-------------|
| `setup-terraform-backend.sh` | Create S3 bucket and DynamoDB for state (idempotent, auto-saves config) | Once, safe to re-run |
| `setup-github-oidc.sh` | Setup GitHub Actions OIDC authentication | Once, for CI/CD setup |
| `generate-cert.sh` | Generate self-signed SSL certificates | For testing HTTPS (optional) |
| `README.md` | Scripts documentation | Reference for script usage |

---

## Documentation (`docs/`)

| File | Lines | Purpose | Read Time |
|------|-------|---------|-----------|
| `ARCHITECTURE.md` | 400+ | System architecture, design decisions | 20 min |
| `SECURITY.md` | 1100+ | Security implementation, compliance | 30 min |
| `RUNBOOK.md` | 1200+ | Operations procedures, troubleshooting | 30 min |

**ARCHITECTURE.md** covers:
- Architecture diagrams
- Component descriptions
- Network design
- Security architecture
- Data flow
- High availability
- Disaster recovery
- Design decisions

**SECURITY.md** covers:
- Security principles
- Network security
- IAM roles
- Data encryption
- Application security
- Compliance (CIS, PCI-DSS, HIPAA, SOC 2)
- Threat model
- Incident response

**RUNBOOK.md** covers:
- Getting started
- Initial setup
- Deployment procedures
- Routine operations
- Monitoring and alerting
- Troubleshooting
- Disaster recovery
- Emergency procedures

---

## Configuration Files

### Terraform Configuration
- `terraform/modules/*/versions.tf` - Provider version constraints
- `terraform/modules/*/variables.tf` - Input variable definitions
- `terraform/modules/*/outputs.tf` - Output value definitions

### Linting and Validation
- `.tflint.hcl` - Terraform linting rules
- `.markdownlint.json` - Markdown linting rules
- `.pre-commit-config.yaml` - Pre-commit hooks configuration

### Docker Configuration
- `app/Dockerfile` - Multi-stage Docker build
- `app/docker-compose.yml` - Local development setup
- `app/.dockerignore` - Docker build exclusions

---

## File Statistics

### Code Statistics
- **Terraform Files**: 26 files, ~3,500+ lines
- **Python Code**: 1 file, 500+ lines
- **Shell Scripts**: 3 files, 600+ lines
- **GitHub Actions**: 4 workflows, 700+ lines

### Documentation Statistics
- **Total Documentation**: 7 files, 4,700+ lines
- **Main Docs**: 3 files (README, QUICK_START, DEPLOYMENT_GUIDE)
- **Technical Docs**: 3 files (ARCHITECTURE, SECURITY, RUNBOOK)
- **Module Docs**: 5 files (one per Terraform module)

### Total Project Size
- **Total Files**: ~50 files
- **Total Lines**: ~9,500+ lines
- **Languages**: HCL (Terraform), Python, Shell, YAML, Markdown

---

## Reading Order for Understanding

### Quick Understanding (30 minutes)
1. `README_FOR_TESTING.md` (5 min) ← Start here
2. `HOW_IT_WORKS.md` (20 min) ← Understand system
3. `README.md` (5 min) ← Project overview

### Medium Understanding (2 hours)
1. Quick Understanding (above)
2. `QUICK_START.md` (15 min)
3. `docs/ARCHITECTURE.md` (30 min)
4. Review Terraform module main.tf files (45 min)

### Deep Understanding (4 hours)
1. Medium Understanding (above)
2. `DEPLOYMENT_GUIDE.md` (30 min)
3. `docs/SECURITY.md` (30 min)
4. `docs/RUNBOOK.md` (30 min)
5. Review all Terraform modules (60 min)
6. Review Flask application (30 min)

---

## Most Important Files (Top 10)

1. **README_FOR_TESTING.md** - Testing guide
2. **HOW_IT_WORKS.md** - System explanation
3. **QUICK_START.md** - Fast deployment
4. **terraform/environments/dev/main.tf** - Infrastructure code
5. **app/src/app.py** - Application code
6. **docs/ARCHITECTURE.md** - Architecture details
7. **docs/SECURITY.md** - Security implementation
8. **docs/RUNBOOK.md** - Operations procedures
9. **.github/workflows/tests.yml** - CI/CD pipeline
10. **Makefile** - Convenience commands

---

## Files You Can Ignore

**Generated Files** (auto-generated, don't edit):
- `.terraform/` - Terraform cache
- `.terraform.lock.hcl` - Terraform lock file
- `*.tfplan` - Terraform plan files
- `terraform.tfstate*` - State files (sensitive!)

**Optional Configuration Files**:
- `.pre-commit-config.yaml` - Development setup
- `.tflint.hcl` - Linting config
- `.markdownlint.json` - Markdown config
- `scripts/generate-cert.sh` - Self-signed certs (rarely needed)

---

## Quick File Finder

**Need to understand architecture?**
→ `HOW_IT_WORKS.md` + `docs/ARCHITECTURE.md`

**Need to deploy?**
→ `QUICK_START.md` or `DEPLOYMENT_GUIDE.md`

**Need to troubleshoot?**
→ `docs/RUNBOOK.md` (Troubleshooting section)

**Need to explain security?**
→ `docs/SECURITY.md`

**Need to understand costs?**
→ `HOW_IT_WORKS.md` (Cost Breakdown section)

**Need to understand CI/CD?**
→ `.github/workflows/` + `HOW_IT_WORKS.md` (CI/CD section)

**Need to modify infrastructure?**
→ `terraform/modules/` (specific module)

**Need to modify application?**
→ `app/src/app.py`

---

## Command Summary

```bash
# Testing
make validate ENV=dev    # Validate Terraform
make apply ENV=dev       # Deploy infrastructure
make destroy ENV=dev     # Destroy infrastructure
make health-check ENV=dev # Test application

# Documentation
cat README_FOR_TESTING.md  # How to test
cat HOW_IT_WORKS.md        # How it works
cat QUICK_START.md         # Quick deployment
cat DEPLOYMENT_GUIDE.md    # Full deployment

# Local Development
cd app && docker-compose up -d  # Start local app
curl http://localhost:5001/health # Test local app
docker-compose down -v      # Stop local app
```

---

**Use this file as your project map! 🗺️**
