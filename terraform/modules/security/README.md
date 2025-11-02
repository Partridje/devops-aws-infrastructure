# Security Module

Production-ready security groups following AWS best practices and the principle of least privilege. Creates a layered security architecture with isolated security groups for each tier.

## Architecture

This module implements a defense-in-depth strategy with multiple security layers:

```
                           Internet
                              │
                              ▼
                    ┌──────────────────┐
                    │  ALB Security    │
                    │  Group           │
                    │  - Port 80/443   │
                    │  - From 0.0.0.0  │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Application     │
                    │  Security Group  │
                    │  - Port 5001     │
                    │  - From ALB only │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  RDS Security    │
                    │  Group           │
                    │  - Port 5432     │
                    │  - From App only │
                    └──────────────────┘
```

## Features

- ✅ **Least Privilege**: Each security group only allows necessary traffic
- ✅ **Layer Isolation**: ALB → Application → Database flow enforcement
- ✅ **Stateful Firewall**: Automatic return traffic handling
- ✅ **Referenced Security Groups**: No hardcoded IPs between tiers
- ✅ **Optional Bastion**: SSH access (disabled by default, use SSM instead)
- ✅ **VPC Endpoints Support**: Security group for interface endpoints
- ✅ **Extensible**: Custom security group support
- ✅ **Well-Tagged**: Automatic tagging for all resources

## Security Groups Created

### 1. ALB Security Group
- **Purpose**: Public-facing load balancer
- **Inbound**:
  - HTTP (80) from 0.0.0.0/0
  - HTTPS (443) from 0.0.0.0/0
- **Outbound**:
  - Application port to Application SG
  - HTTPS for health checks

### 2. Application Security Group
- **Purpose**: EC2 instances, ECS tasks, Lambda in VPC
- **Inbound**:
  - Application port from ALB SG only
  - Optional: SSH from Bastion SG
- **Outbound**:
  - HTTP/HTTPS to internet (via NAT)
  - RDS port to RDS SG
  - DNS (53 UDP/TCP)
  - NTP (123 UDP) for time sync

### 3. RDS Security Group
- **Purpose**: Database instances
- **Inbound**:
  - PostgreSQL (5432) from Application SG only
  - Optional: PostgreSQL from Bastion SG
- **Outbound**:
  - None needed (stateful firewall)

### 4. Bastion Security Group (Optional)
- **Purpose**: SSH jump host
- **Inbound**:
  - SSH (22) from specified CIDR
- **Outbound**:
  - SSH to Application SG
- **⚠️ NOT RECOMMENDED**: Use AWS Systems Manager Session Manager instead

### 5. VPC Endpoints Security Group (Optional)
- **Purpose**: Interface VPC endpoints (SSM, ECR, Secrets Manager)
- **Inbound**:
  - HTTPS (443) from VPC CIDR
- **Outbound**:
  - None needed

### 6. Custom Security Group (Optional)
- **Purpose**: Additional services (Redis, ElastiCache, etc.)
- **Rules**: Fully customizable via variables

## Usage

### Basic Example

```hcl
module "security" {
  source = "../../modules/security"

  name_prefix = "myapp-dev"
  environment = "dev"
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = "10.0.0.0/16"

  application_port = 5001
  rds_port         = 5432

  tags = {
    Project = "MyApp"
    Team    = "DevOps"
  }
}
```

### Production Example with Custom Security Group

```hcl
module "security" {
  source = "../../modules/security"

  name_prefix = "myapp-prod"
  environment = "prod"
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = "10.0.0.0/16"

  application_port = 5001
  rds_port         = 5432

  # VPC Endpoints for SSM, Secrets Manager
  enable_vpc_endpoint_sg = true

  # Additional security group for Redis
  create_custom_sg      = true
  custom_sg_description = "Security group for Redis ElastiCache"

  custom_sg_ingress_rules = {
    redis_from_app = {
      description = "Allow Redis from application"
      cidr_ipv4   = "10.0.0.0/16"
      from_port   = 6379
      to_port     = 6379
      ip_protocol = "tcp"
    }
  }

  custom_sg_egress_rules = {
    all_traffic = {
      description = "Allow all outbound"
      cidr_ipv4   = "0.0.0.0/0"
      from_port   = 0
      to_port     = 0
      ip_protocol = "-1"
    }
  }

  tags = {
    Project     = "MyApp"
    Team        = "DevOps"
    Environment = "Production"
  }
}
```

### Example with Bastion (Not Recommended)

```hcl
module "security" {
  source = "../../modules/security"

  name_prefix = "myapp-dev"
  environment = "dev"
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = "10.0.0.0/16"

  # Enable bastion (use SSM Session Manager instead in production)
  enable_bastion       = true
  bastion_allowed_cidr = "203.0.113.0/24"  # Your office IP

  tags = {
    Project = "MyApp"
    Team    = "DevOps"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix for all resource names | `string` | n/a | yes |
| vpc_id | ID of the VPC | `string` | n/a | yes |
| vpc_cidr | CIDR block of the VPC | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| application_port | Application listening port | `number` | `5001` | no |
| rds_port | RDS database port | `number` | `5432` | no |
| enable_bastion | Enable bastion security group | `bool` | `false` | no |
| bastion_allowed_cidr | CIDR allowed to SSH to bastion | `string` | `"0.0.0.0/0"` | no |
| enable_vpc_endpoint_sg | Create VPC endpoints security group | `bool` | `true` | no |
| create_custom_sg | Create custom security group | `bool` | `false` | no |
| custom_sg_description | Description for custom SG | `string` | `"Custom security group for additional services"` | no |
| custom_sg_ingress_rules | Ingress rules for custom SG | `map(object)` | `{}` | no |
| custom_sg_egress_rules | Egress rules for custom SG | `map(object)` | `{}` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| alb_security_group_id | ID of ALB security group |
| application_security_group_id | ID of application security group |
| rds_security_group_id | ID of RDS security group |
| bastion_security_group_id | ID of bastion security group (if enabled) |
| vpc_endpoints_security_group_id | ID of VPC endpoints security group (if enabled) |
| custom_security_group_id | ID of custom security group (if created) |
| all_security_group_ids | Map of all security group IDs |

## Security Best Practices

### ✅ Implemented

1. **Least Privilege**: Only necessary ports and protocols allowed
2. **Referenced Security Groups**: Uses SG IDs instead of CIDR blocks between tiers
3. **Stateful Firewall**: Leverages AWS security group stateful nature
4. **No Inbound SSH**: Disabled by default (use SSM Session Manager)
5. **Egress Control**: Application SG only allows specific outbound traffic
6. **Database Isolation**: RDS SG only accepts traffic from application tier
7. **Logging Ready**: Works with VPC Flow Logs for traffic analysis

### 🔒 Additional Recommendations

1. **Enable GuardDuty**: Threat detection for VPC
   ```bash
   aws guardduty create-detector --enable
   ```

2. **Use AWS Config**: Monitor security group changes
   ```bash
   aws configservice put-config-rule --config-rule file://sg-rules.json
   ```

3. **Regular Audits**: Review security group rules quarterly
   ```bash
   aws ec2 describe-security-groups --query 'SecurityGroups[*].[GroupId,GroupName,IpPermissions]'
   ```

4. **Use SSM Session Manager**: No SSH keys, no open port 22
   ```bash
   aws ssm start-session --target i-1234567890abcdef0
   ```

5. **Enable CloudTrail**: Audit security group changes
   ```bash
   aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::EC2::SecurityGroup
   ```

## Traffic Flow Examples

### Successful Request Flow
```
User → ALB (80/443) → Application (5001) → RDS (5432)
  ✓       ✓                ✓                 ✓
```

### Blocked Attempts
```
User → RDS (5432)                    ❌ Blocked (no direct access)
Internet → Application (5001)        ❌ Blocked (ALB only)
Application → RDS (3306)             ❌ Blocked (wrong port)
External IP → Bastion (22)           ❌ Blocked (CIDR not allowed)
```

## Troubleshooting

### Issue: Application cannot connect to RDS

**Check 1**: Verify security group rules
```bash
# Check RDS security group
aws ec2 describe-security-groups --group-ids sg-xxx --query 'SecurityGroups[0].IpPermissions'

# Check application security group
aws ec2 describe-security-groups --group-ids sg-yyy --query 'SecurityGroups[0].IpPermissionsEgress'
```

**Check 2**: Verify instances are using correct security groups
```bash
aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[0].Instances[0].SecurityGroups'
```

**Check 3**: Test connectivity
```bash
# From application instance
telnet rds-endpoint 5432
nc -zv rds-endpoint 5432
```

### Issue: ALB health checks failing

**Check 1**: ALB can reach targets
```bash
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...
```

**Check 2**: Application SG allows traffic from ALB
```bash
aws ec2 describe-security-groups --group-ids sg-app --query 'SecurityGroups[0].IpPermissions[?contains(UserIdGroupPairs[].GroupId, `sg-alb`)]'
```

### Issue: Cannot SSH to instances via bastion

**Recommendation**: Don't use SSH! Use SSM Session Manager:
```bash
aws ssm start-session --target i-xxx
```

If you must use bastion:
```bash
# Check bastion SG allows your IP
aws ec2 describe-security-groups --group-ids sg-bastion

# Check application SG allows bastion
aws ec2 describe-security-groups --group-ids sg-app --query 'SecurityGroups[0].IpPermissions[?contains(UserIdGroupPairs[].GroupId, `sg-bastion`)]'
```

## Compliance

This module helps meet the following compliance requirements:

- **CIS AWS Foundations**: Section 4 (Networking)
- **NIST 800-53**: SC-7 (Boundary Protection)
- **PCI DSS**: Requirement 1 (Firewall Configuration)
- **HIPAA**: Access Control (§164.312(a)(1))
- **SOC 2**: Logical Access Controls

## Migration from Old Security Groups

If migrating from existing security groups:

1. **Create new security groups** with this module
2. **Update one tier at a time**: Start with RDS, then App, then ALB
3. **Test thoroughly** between each tier
4. **Remove old security groups** after validation

```bash
# Export old rules for reference
aws ec2 describe-security-groups --group-ids sg-old > old-sg-backup.json

# Apply new security groups
terraform apply

# Update instances gradually
aws ec2 modify-instance-attribute --instance-id i-xxx --groups sg-new-app sg-new-xxx
```

## Examples

See the `examples/` directory:
- `examples/basic-security/` - Minimal security setup
- `examples/production-security/` - Full production security
- `examples/custom-security/` - Custom security group examples

## Authors

Created and maintained by DevOps Team

## License

MIT Licensed. See LICENSE for full details.
