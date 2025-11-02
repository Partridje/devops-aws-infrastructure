# EC2 with ALB and Auto Scaling Terraform Module

Production-ready compute module with Application Load Balancer, Auto Scaling Group, Launch Template, and comprehensive monitoring. Automatically deploys application instances with health checks, scaling policies, and CloudWatch integration.

## Features

- ✅ **Application Load Balancer**: HTTP/HTTPS with SSL/TLS termination
- ✅ **Auto Scaling Group**: Dynamic scaling based on metrics
- ✅ **Launch Template**: IMDSv2, encrypted EBS, CloudWatch agent
- ✅ **Health Checks**: ALB health checks with configurable thresholds
- ✅ **IAM Roles**: SSM Session Manager, Secrets Manager, ECR access
- ✅ **Scaling Policies**: CPU-based and ALB request-based
- ✅ **CloudWatch Monitoring**: Logs, metrics, and alarms
- ✅ **Session Stickiness**: Optional cookie-based stickiness
- ✅ **Rolling Updates**: Zero-downtime deployments
- ✅ **User Data**: Automated application installation

## Architecture

```
                    Internet
                       │
                       ▼
              ┌─────────────────┐
              │  Application    │
              │  Load Balancer  │
              │  (Public)       │
              └─────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
   ┌────────┐    ┌────────┐    ┌────────┐
   │  EC2   │    │  EC2   │    │  EC2   │
   │ (AZ 1) │    │ (AZ 2) │    │ (AZ 3) │
   └────────┘    └────────┘    └────────┘
   Auto Scaling Group (2-4 instances)
        │
        ▼
   CloudWatch Logs & Metrics
```

## Usage

### Basic Example

```hcl
module "ec2" {
  source = "../../modules/ec2"

  name_prefix = "myapp-dev"
  environment = "dev"
  vpc_id      = module.vpc.vpc_id

  # Network configuration
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Security groups
  alb_security_group_ids         = [module.security.alb_security_group_id]
  application_security_group_ids = [module.security.application_security_group_id]

  # Application configuration
  application_port = 5001
  db_secret_arn    = module.rds.db_secret_arn

  # Instance configuration
  instance_type = "t3.micro"

  # Auto Scaling
  asg_min_size         = 1
  asg_max_size         = 2
  asg_desired_capacity = 1

  tags = {
    Project = "MyApp"
    Team    = "DevOps"
  }
}
```

### Production Example

```hcl
module "ec2" {
  source = "../../modules/ec2"

  name_prefix = "myapp-prod"
  environment = "prod"
  vpc_id      = module.vpc.vpc_id

  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  alb_security_group_ids         = [module.security.alb_security_group_id]
  application_security_group_ids = [module.security.application_security_group_id]

  # Application
  application_port   = 5001
  app_version        = "v1.2.3"
  ecr_repository_url = "123456789012.dkr.ecr.eu-north-1.amazonaws.com/myapp"
  db_secret_arn      = module.rds.db_secret_arn

  # Instance configuration
  instance_type         = "t3.small"
  root_volume_size      = 30
  root_volume_type      = "gp3"
  enable_detailed_monitoring = true

  # Auto Scaling
  asg_min_size         = 2
  asg_max_size         = 10
  asg_desired_capacity = 4

  # Scaling policies
  enable_cpu_scaling = true
  cpu_target_value   = 70
  enable_alb_scaling = true
  alb_requests_per_target = 1000

  # Load Balancer
  enable_deletion_protection = true
  certificate_arn            = aws_acm_certificate.main.arn
  enable_https_redirect      = true
  ssl_policy                 = "ELBSecurityPolicy-TLS-1-2-2017-01"

  # Health checks
  health_check_path              = "/health"
  health_check_interval          = 30
  health_check_healthy_threshold = 2
  deregistration_delay           = 30

  # Monitoring
  create_monitoring_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]
  log_retention_days       = 30

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
| vpc_id | VPC ID | `string` | n/a | yes |
| public_subnet_ids | Public subnet IDs for ALB | `list(string)` | n/a | yes |
| private_subnet_ids | Private subnet IDs for instances | `list(string)` | n/a | yes |
| alb_security_group_ids | ALB security group IDs | `list(string)` | n/a | yes |
| application_security_group_ids | Application security group IDs | `list(string)` | n/a | yes |
| instance_type | EC2 instance type | `string` | `"t3.small"` | no |
| asg_min_size | ASG minimum size | `number` | `2` | no |
| asg_max_size | ASG maximum size | `number` | `4` | no |
| application_port | Application port | `number` | `5001` | no |
| certificate_arn | ACM certificate ARN for HTTPS | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| alb_dns_name | DNS name of ALB |
| alb_url | HTTP URL of ALB |
| alb_https_url | HTTPS URL of ALB (if enabled) |
| asg_name | Auto Scaling Group name |
| target_group_arn | Target Group ARN |

## User Data Script

The module includes a comprehensive user data script that:

1. **Installs packages**: Docker, AWS CLI, CloudWatch agent, PostgreSQL client
2. **Configures CloudWatch**: Logs and metrics collection
3. **Retrieves credentials**: From Secrets Manager
4. **Starts application**: Via Docker or direct Flask installation
5. **Health checks**: Waits for application to be healthy

### Application Deployment Options

**Option 1: Docker from ECR**
```hcl
ecr_repository_url = "123456789012.dkr.ecr.eu-north-1.amazonaws.com/myapp"
app_version        = "v1.2.3"
```

**Option 2: Built-in Flask Application**
```hcl
# Leave ecr_repository_url empty
# Module will install Flask app directly
```

## Scaling Policies

### CPU-Based Scaling (Recommended)
```hcl
enable_cpu_scaling = true
cpu_target_value   = 70  # Scale when CPU > 70%
```

### ALB Request-Based Scaling
```hcl
enable_alb_scaling = true
alb_requests_per_target = 1000  # 1000 requests per instance
```

### Simple Scaling with Alarms
```hcl
enable_simple_scaling = true
# Scales up when CPU > 80%, down when CPU < 20%
```

## Monitoring

### CloudWatch Alarms

Automatically created alarms:
- **Unhealthy Hosts**: Alerts when targets are unhealthy
- **High Response Time**: Alerts when response time > 1s
- **HTTP 5xx Errors**: Alerts on application errors

### CloudWatch Logs

Application logs are sent to CloudWatch:
- `/aws/ec2/{name}-application/{instance-id}/application`
- `/aws/ec2/{name}-application/{instance-id}/user-data`
- `/aws/ec2/{name}-application/{instance-id}/docker`

### View Logs
```bash
# Tail application logs
aws logs tail /aws/ec2/myapp-dev-application --follow

# Search for errors
aws logs filter-log-events \
  --log-group-name /aws/ec2/myapp-dev-application \
  --filter-pattern "ERROR"
```

## Health Checks

### ALB Health Check Configuration

```hcl
health_check_path              = "/health"
health_check_interval          = 30
health_check_timeout           = 5
health_check_healthy_threshold = 2
health_check_unhealthy_threshold = 2
```

### Application Health Endpoint

Your application should implement:
```python
@app.route('/health')
def health():
    return jsonify({'status': 'healthy'}), 200
```

## Accessing Instances

### SSH via SSM Session Manager (Recommended)
```bash
# List instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=myapp-prod-asg-instance" \
  --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,State.Name]'

# Connect to instance
aws ssm start-session --target i-1234567890abcdef0
```

### No SSH keys required!

## Rolling Updates

Update the application version:
```bash
# Update launch template with new version
terraform apply -var="app_version=v1.2.4"

# ASG will perform rolling update automatically
# Maintains 90% healthy instances during update
```

## Troubleshooting

### Issue: Instances not becoming healthy

**Check 1**: View user data logs
```bash
aws ssm start-session --target i-xxx
cat /var/log/user-data.log
```

**Check 2**: Check application logs
```bash
journalctl -u application -f
```

**Check 3**: Test health endpoint locally
```bash
curl http://localhost:5001/health
```

### Issue: ALB returning 502 errors

**Check 1**: Target health
```bash
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn)
```

**Check 2**: Security group rules
```bash
# Ensure app SG allows traffic from ALB SG on application port
```

### Issue: Auto Scaling not working

**Check 1**: CloudWatch metrics
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=myapp-prod-asg \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Cost Optimization

### Development
- `instance_type = "t3.micro"` (Free Tier eligible)
- `asg_min_size = 1, asg_max_size = 2`
- `enable_detailed_monitoring = false`
- Single AZ deployment

### Production
- Use Reserved Instances or Savings Plans
- Right-size instances based on metrics
- Enable autoscaling to match demand
- Consider Graviton instances (t4g, m6g) for better price/performance

## Examples

Complete examples available in `examples/` directory:
- `examples/basic-ec2/` - Minimal setup
- `examples/production-ec2/` - Full production deployment
- `examples/docker-deployment/` - ECR-based deployment

## Authors

Created and maintained by DevOps Team

## License

MIT Licensed. See LICENSE for full details.
