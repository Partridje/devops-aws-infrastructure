# Deployment Guide

This guide explains the two-stage deployment process: Infrastructure deployment and Application deployment.

## Overview

The deployment process is separated into two independent workflows:

1. **Infrastructure Deployment** (`terraform-apply.yml`) - Creates AWS resources
2. **Application Deployment** (`app-deploy.yml`) - Deploys application code

This separation provides:
- Clear boundary between infrastructure and application changes
- Ability to update application without touching infrastructure
- Better control over when deployments happen
- Easier troubleshooting and rollback

---

## Prerequisites

### Required GitHub Secrets

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `AWS_ROLE_ARN` | IAM Role ARN for OIDC authentication | `arn:aws:iam::123456789:role/github-actions` |
| `ALERT_EMAIL_ADDRESSES` | Email addresses for CloudWatch alarms | `["ops@example.com"]` |

Setup instructions: [GITHUB_SECRETS_SETUP.md](GITHUB_SECRETS_SETUP.md)

---

## Stage 1: Infrastructure Deployment

Infrastructure must be deployed **first** before any application deployment.

### What Gets Deployed

- VPC, Subnets, Security Groups, Route Tables
- RDS PostgreSQL Database (Multi-AZ in prod)
- ECR Repository (`demo-app-{env}-app`)
- Application Load Balancer
- Auto Scaling Group (with Launch Template)
- CloudWatch Alarms & Log Groups
- SNS Topics for alerts
- IAM Roles & Policies

### Deployment Steps

1. **Navigate to Actions**
   ```
   GitHub → Actions → Terraform Apply
   ```

2. **Run Workflow**
   - Click "Run workflow"
   - Select environment: `dev` or `prod`
   - Click "Run workflow"

3. **Monitor Progress**
   - Initial setup: ~2 minutes
   - RDS creation: ~10-15 minutes (Multi-AZ in prod)
   - Total time: ~15-20 minutes

4. **Verify Completion**
   After successful completion, note the outputs:
   - ALB DNS name
   - ECR repository URL
   - ASG name

### Terraform Plan (Optional)

To preview changes before applying:

```
GitHub → Actions → Terraform Plan
Select environment → Run workflow
```

This shows what will be created/modified/destroyed without making changes.

---

## Stage 2: Application Deployment

Application deployment is **manual only** and requires existing infrastructure.

### What Happens

1. **Infrastructure Verification**
   - Checks ECR repository exists
   - Checks Auto Scaling Group exists
   - Checks Load Balancer exists
   - Fails fast if infrastructure is missing

2. **Build & Push**
   - Builds Docker image from `app/` directory
   - Runs Trivy security scan
   - Tests container locally
   - Pushes to ECR with tags: `{sha}` and `latest`

3. **Deploy**
   - Triggers ASG Instance Refresh
   - **Dev**: Rolling update (90% healthy, faster)
   - **Prod**: Blue-Green deployment (100% healthy, checkpoints)
   - Waits for refresh to complete
   - Runs smoke tests

### Deployment Steps

1. **Navigate to Actions**
   ```
   GitHub → Actions → Deploy Application
   ```

2. **Run Workflow**
   - Click "Run workflow"
   - **Environment**: Select `dev` or `prod`
   - **Image Tag** (optional): Leave empty to use latest commit SHA
   - Click "Run workflow"

3. **Monitor Progress**
   - Infrastructure verification: ~30 seconds
   - Build & push: ~5 minutes
   - Instance refresh: ~10-15 minutes
   - Total time: ~15-20 minutes

4. **Verify Deployment**
   Check the deployment summary at the end of the workflow run:
   ```
   Environment: prod
   Image: 123456789.dkr.ecr.eu-north-1.amazonaws.com/demo-app-prod-app:abc123
   ASG: demo-app-prod-asg
   ALB URL: https://demo-app-prod-alb-xyz.eu-north-1.elb.amazonaws.com
   ```

---

## Deployment Strategies

### Development Environment

- **Strategy**: Rolling Update
- **Min Healthy**: 90%
- **Instance Warmup**: 300 seconds
- **Downtime**: Minimal (some requests may hit old instances)
- **Rollback**: Manual via workflow re-run

### Production Environment

- **Strategy**: Blue-Green with Checkpoints
- **Min Healthy**: 100%
- **Instance Warmup**: 300 seconds
- **Checkpoints**: At 50% (pauses for 5 minutes)
- **Downtime**: Zero (always 100% capacity)
- **Rollback**: Automatic cancellation on failure

---

## Typical Workflows

### Initial Setup (New Environment)

```bash
1. Deploy Infrastructure
   └─ terraform-apply.yml (dev)
   └─ Wait 15-20 minutes

2. Deploy Application
   └─ app-deploy.yml (dev)
   └─ Wait 15-20 minutes

3. Verify
   └─ curl http://{alb-url}/health
```

### Application Update

```bash
1. Make changes to app/ directory
2. Commit and push to branch
3. Create PR and review
4. Merge to main
5. Manually trigger app-deploy.yml
   └─ Select environment
   └─ Wait for deployment
6. Verify via smoke tests
```

### Infrastructure Update

```bash
1. Make changes to terraform/ directory
2. Run terraform-plan.yml to preview
3. Review plan output
4. Run terraform-apply.yml
   └─ Infrastructure updates
   └─ May trigger ASG instance replacement
5. Application continues running (no app-deploy needed)
```

---

## Troubleshooting

### Infrastructure Deployment Fails

**RDS Creation Timeout**
- RDS Multi-AZ takes 10-15 minutes
- Check CloudWatch logs: `/aws/rds/instance/demo-app-{env}-db`
- Verify subnets are in different AZs

**VPC Creation Fails**
- Check if CIDR overlaps with existing VPCs
- Verify region has enough available IPs
- Check service quotas

**Terraform State Lock**
- Another apply/destroy is running
- Wait for it to complete or force-unlock:
  ```bash
  terraform force-unlock <lock-id>
  ```

### Application Deployment Fails

**Infrastructure Verification Fails**
```
Error: ECR repository not found: demo-app-dev-app
Solution: Run terraform-apply.yml first
```

**Build Fails**
- Check Docker build logs
- Verify app/Dockerfile is correct
- Check if all dependencies are available

**Instance Refresh Fails**
- Check ASG activity history
- Verify EC2 instances can pull from ECR
- Check CloudWatch logs: `/aws/ec2/demo-app-{env}`
- Review health check failures

**Smoke Tests Fail**
- Check ALB target group health
- Verify security groups allow traffic
- Check application logs in CloudWatch
- Test endpoints manually:
  ```bash
  curl http://{alb-url}/health
  curl http://{alb-url}/db
  ```

###Rollback Application Deployment

If deployment fails, the workflow automatically cancels the instance refresh.

**Manual Rollback**:
1. Re-run app-deploy.yml with previous image tag:
   ```
   Image Tag: <previous-commit-sha>
   ```

2. Or deploy previous version from ECR:
   ```bash
   aws ecr describe-images \
     --repository-name demo-app-prod-app \
     --region eu-north-1
   ```

### Rollback Infrastructure

**Before Applying**:
- Use terraform-plan.yml to preview changes
- Review the plan carefully

**After Applying**:
- Terraform doesn't support automatic rollback
- Options:
  1. Revert git commit and re-run terraform-apply
  2. Manually fix in AWS Console (not recommended)
  3. Use terraform state commands (advanced)

---

## Best Practices

### Infrastructure

1. **Always run terraform-plan first** before terraform-apply
2. **Review plan output** carefully, especially deletions
3. **Use dev environment** for testing infrastructure changes
4. **Monitor CloudWatch** during and after deployment
5. **Keep terraform state** in S3 backend (already configured)

### Application

1. **Test locally** before deploying
2. **Use dev environment** for testing application changes
3. **Monitor logs** during deployment
4. **Run smoke tests** manually if workflow tests are insufficient
5. **Deploy during low-traffic periods** for production

### Security

1. **Never commit secrets** to git
2. **Use GitHub Secrets** for sensitive data
3. **Review IAM policies** regularly
4. **Keep Docker images** up to date with security patches
5. **Monitor Trivy scan results** in workflow output

---

## Environment Differences

| Feature | Dev | Prod |
|---------|-----|------|
| **RDS** | Single-AZ, t3.micro | Multi-AZ, t3.small |
| **EC2** | 1-2 instances, t3.micro | 2-6 instances, t3.small |
| **Backup** | 1 day retention | 30 days retention |
| **Monitoring** | Basic | Enhanced + Performance Insights |
| **Deployment** | Rolling (90%) | Blue-Green (100%) |
| **Protection** | Disabled | Disabled (for destroy testing) |
| **HTTPS** | HTTP only | HTTPS with SSL |
| **WAF** | Disabled | Disabled |

---

## Complete Project Cleanup

When you want to **completely remove the project** (including backend):

### Step 1: Destroy Infrastructure

```bash
# Via GitHub Actions
GitHub → Actions → Terraform Destroy → Run workflow (prod/dev)

# Or locally
make destroy ENV=prod
make destroy ENV=dev
```

### Step 2: Cleanup Backend (Optional)

**⚠️ WARNING**: This removes ALL Terraform state permanently!

```bash
./scripts/cleanup-terraform-backend.sh
# Type 'DELETE' to confirm
```

This will remove:
- S3 bucket with Terraform state
- S3 bucket with logs
- DynamoDB table for state locking

**Why keep backend after destroy?**
- Preserves state history
- Allows infrastructure recreation
- Prevents state drift issues
- Required for multiple environments

**When to cleanup backend?**
- Project is being decommissioned
- Moving to different backend
- Complete fresh start needed

---

## Next Steps

- [Testing Guide](TESTING_GUIDE.md) - How to test your deployment
- [Production Verification](PRODUCTION_VERIFICATION_CHECKLIST.md) - Production readiness checklist
- [Monitoring Setup](SNS_SETUP.md) - Configure alerts and notifications
- [Secrets Rotation](SECRETS_ROTATION.md) - Rotate database credentials

---

## Quick Reference

### GitHub Actions Workflows

| Workflow | Purpose | Trigger | Duration |
|----------|---------|---------|----------|
| `terraform-plan.yml` | Preview infrastructure changes | Manual | 2-3 min |
| `terraform-apply.yml` | Deploy infrastructure | Manual | 15-20 min |
| `terraform-destroy.yml` | Destroy infrastructure | Manual | 20-25 min |
| `app-deploy.yml` | Deploy application | Manual | 15-20 min |

### AWS Resources

| Resource | Dev | Prod |
|----------|-----|------|
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| Region | `eu-north-1` | `eu-north-1` |
| ECR Repo | `demo-app-dev-app` | `demo-app-prod-app` |
| DB Name | `appdb` | `appdb` |
| App Port | `5001` | `5001` |

### Useful Commands

```bash
# Check infrastructure status
aws elbv2 describe-load-balancers --region eu-north-1
aws autoscaling describe-auto-scaling-groups --region eu-north-1
aws rds describe-db-instances --region eu-north-1
aws ecr describe-repositories --region eu-north-1

# Check application logs
aws logs tail /aws/ec2/demo-app-prod --follow --region eu-north-1

# Check ASG activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name demo-app-prod-asg \
  --max-records 10 \
  --region eu-north-1

# List Docker images
aws ecr list-images \
  --repository-name demo-app-prod-app \
  --region eu-north-1
```
