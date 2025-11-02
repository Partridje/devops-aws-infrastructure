# VPC Terraform Module

Production-ready VPC module that creates a highly available network architecture with multiple availability zones, public and private subnets, NAT gateways, and VPC flow logs.

## Architecture

This module creates a three-tier network architecture:

1. **Public Tier**: ALB, NAT Gateways, Bastion hosts (optional)
2. **Private Tier**: Application servers, ECS tasks, Lambda functions
3. **Database Tier**: RDS, ElastiCache, isolated from internet

```
┌─────────────────────────────────────────────────────────────┐
│                         VPC (10.0.0.0/16)                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  │
│  │   AZ 1        │  │   AZ 2        │  │   AZ 3        │  │
│  ├───────────────┤  ├───────────────┤  ├───────────────┤  │
│  │ Public Subnet │  │ Public Subnet │  │ Public Subnet │  │
│  │ 10.0.0.0/24   │  │ 10.0.1.0/24   │  │ 10.0.2.0/24   │  │
│  │  - ALB        │  │  - ALB        │  │  - ALB        │  │
│  │  - NAT GW     │  │  - NAT GW     │  │  - NAT GW     │  │
│  └───────────────┘  └───────────────┘  └───────────────┘  │
│                                                              │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  │
│  │Private Subnet │  │Private Subnet │  │Private Subnet │  │
│  │ 10.0.10.0/24  │  │ 10.0.11.0/24  │  │ 10.0.12.0/24  │  │
│  │  - EC2 (App)  │  │  - EC2 (App)  │  │  - EC2 (App)  │  │
│  └───────────────┘  └───────────────┘  └───────────────┘  │
│                                                              │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  │
│  │   Database    │  │   Database    │  │   Database    │  │
│  │   Subnet      │  │   Subnet      │  │   Subnet      │  │
│  │ 10.0.20.0/24  │  │ 10.0.21.0/24  │  │ 10.0.22.0/24  │  │
│  │  - RDS        │  │  - RDS        │  │  - RDS        │  │
│  └───────────────┘  └───────────────┘  └───────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Features

- ✅ **Multi-AZ**: Deploys across 2-3 Availability Zones for high availability
- ✅ **Three-tier architecture**: Public, Private, and Database subnets
- ✅ **NAT Gateways**: One per AZ for HA (or single for cost optimization)
- ✅ **VPC Flow Logs**: Network traffic monitoring to CloudWatch
- ✅ **VPC Endpoints**: S3 and DynamoDB gateway endpoints (no extra cost)
- ✅ **DNS Support**: Enabled for RDS and other services
- ✅ **Internet Gateway**: Public internet access
- ✅ **Isolated Database Tier**: No direct internet route for security

## Usage

### Basic Example

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = "myapp-dev"
  environment  = "dev"
  vpc_cidr     = "10.0.0.0/16"
  aws_region   = "eu-north-1"
  azs_count    = 3

  tags = {
    Project   = "MyApp"
    Team      = "DevOps"
    ManagedBy = "Terraform"
  }
}
```

### Production Example with All Features

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = "myapp-prod"
  environment  = "prod"
  vpc_cidr     = "10.0.0.0/16"
  aws_region   = "eu-north-1"
  azs_count    = 3

  # High Availability - NAT Gateway per AZ
  single_nat_gateway = false

  # VPC Flow Logs
  enable_flow_logs            = true
  flow_logs_retention_days    = 30
  flow_logs_traffic_type      = "ALL"

  # VPC Endpoints (reduce NAT Gateway costs)
  enable_s3_endpoint       = true
  enable_dynamodb_endpoint = true

  # Network ACLs
  manage_default_network_acl = true

  tags = {
    Project     = "MyApp"
    Team        = "DevOps"
    Environment = "Production"
    CostCenter  = "Engineering"
    ManagedBy   = "Terraform"
  }
}
```

### Cost-Optimized Development Example

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = "myapp-dev"
  environment  = "dev"
  vpc_cidr     = "10.0.0.0/16"
  aws_region   = "eu-north-1"
  azs_count    = 2

  # Single NAT Gateway for cost savings
  single_nat_gateway = true

  # Minimal flow logs retention
  enable_flow_logs         = true
  flow_logs_retention_days = 7

  # Enable endpoints to reduce NAT costs
  enable_s3_endpoint       = true
  enable_dynamodb_endpoint = true

  tags = {
    Project     = "MyApp"
    Team        = "DevOps"
    Environment = "Development"
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
| vpc_cidr | CIDR block for VPC | `string` | n/a | yes |
| environment | Environment name (dev, staging, prod) | `string` | n/a | yes |
| aws_region | AWS region where resources will be created | `string` | n/a | yes |
| azs_count | Number of Availability Zones to use | `number` | `3` | no |
| single_nat_gateway | Use a single NAT Gateway for cost optimization | `bool` | `false` | no |
| enable_flow_logs | Enable VPC Flow Logs | `bool` | `true` | no |
| flow_logs_retention_days | Number of days to retain VPC Flow Logs | `number` | `7` | no |
| flow_logs_traffic_type | Type of traffic to log (ACCEPT, REJECT, ALL) | `string` | `"ALL"` | no |
| enable_s3_endpoint | Enable S3 VPC endpoint | `bool` | `true` | no |
| enable_dynamodb_endpoint | Enable DynamoDB VPC endpoint | `bool` | `true` | no |
| manage_default_network_acl | Manage the default Network ACL | `bool` | `false` | no |
| enable_dhcp_options | Enable custom DHCP options | `bool` | `false` | no |
| dhcp_options_domain_name | DNS domain name for DHCP options | `string` | `""` | no |
| dhcp_options_domain_name_servers | List of DNS servers | `list(string)` | `["AmazonProvidedDNS"]` | no |
| tags | Additional tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | The ID of the VPC |
| vpc_arn | The ARN of the VPC |
| vpc_cidr_block | The CIDR block of the VPC |
| public_subnet_ids | List of IDs of public subnets |
| public_subnet_cidrs | List of CIDR blocks of public subnets |
| private_subnet_ids | List of IDs of private subnets |
| private_subnet_cidrs | List of CIDR blocks of private subnets |
| database_subnet_ids | List of IDs of database subnets |
| database_subnet_cidrs | List of CIDR blocks of database subnets |
| nat_gateway_ids | List of NAT Gateway IDs |
| nat_gateway_public_ips | List of public IPs for NAT Gateways |
| internet_gateway_id | The ID of the Internet Gateway |
| availability_zones | List of Availability Zones used |

## CIDR Calculation

The module automatically calculates subnet CIDRs based on the VPC CIDR:

- **Public subnets**: VPC CIDR + /8 (0-2)
- **Private subnets**: VPC CIDR + /8 (10-12)
- **Database subnets**: VPC CIDR + /8 (20-22)

Example with VPC CIDR `10.0.0.0/16`:
- Public: `10.0.0.0/24`, `10.0.1.0/24`, `10.0.2.0/24`
- Private: `10.0.10.0/24`, `10.0.11.0/24`, `10.0.12.0/24`
- Database: `10.0.20.0/24`, `10.0.21.0/24`, `10.0.22.0/24`

## Cost Considerations

### NAT Gateway Costs

- **Per NAT Gateway**: ~$0.045/hour = ~$32/month
- **3 NAT Gateways** (HA): ~$96/month
- **1 NAT Gateway** (cost-optimized): ~$32/month

💡 **Tip**: Use `single_nat_gateway = true` for dev/staging to save ~$64/month

### VPC Endpoints Savings

Using S3 and DynamoDB gateway endpoints can reduce NAT Gateway data transfer costs:
- S3/DynamoDB traffic bypasses NAT Gateway
- No per-GB charges for gateway endpoints
- Estimated savings: $10-50/month depending on usage

### Flow Logs Costs

- CloudWatch Logs ingestion: ~$0.50/GB
- Log storage: ~$0.03/GB/month
- Typical cost for moderate traffic: ~$5-20/month

## Security Best Practices

✅ **Implemented in this module:**

1. ✅ Three-tier subnet architecture
2. ✅ Private subnets with no public IP assignment
3. ✅ Isolated database subnets
4. ✅ VPC Flow Logs enabled by default
5. ✅ VPC endpoints for AWS services
6. ✅ DNS support for secure communication

⚠️ **Additional recommendations:**

1. Enable GuardDuty for threat detection
2. Use Network ACLs for additional security layer
3. Implement security groups (in separate module)
4. Enable CloudTrail for API logging
5. Use AWS Config for compliance checking

## Troubleshooting

### Issue: "Error creating NAT Gateway: Resource limit exceeded"

**Solution**: AWS has a default limit of 5 NAT Gateways per AZ. Request a limit increase.

```bash
aws service-quotas get-service-quota \
  --service-code vpc \
  --quota-code L-FE5A380F
```

### Issue: "Private subnet instances cannot reach internet"

**Checks**:
1. Verify NAT Gateway is in `available` state
2. Check route table has route to NAT Gateway
3. Verify security groups allow outbound traffic
4. Check Network ACLs allow traffic

```bash
# Check NAT Gateway status
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=vpc-xxx"

# Check route tables
aws ec2 describe-route-tables --filter "Name=vpc-id,Values=vpc-xxx"
```

### Issue: "VPC Flow Logs not appearing in CloudWatch"

**Checks**:
1. Wait 10-15 minutes after creation
2. Verify IAM role permissions
3. Check if traffic exists (generate some traffic)
4. Verify CloudWatch log group exists

```bash
# Tail flow logs
aws logs tail /aws/vpc/myapp-dev-flow-logs --follow
```

## Examples

See the `examples/` directory for complete working examples:

- `examples/basic/` - Minimal VPC setup
- `examples/production/` - Full production setup with HA
- `examples/cost-optimized/` - Development setup with cost optimization

## Authors

Created and maintained by DevOps Team

## License

MIT Licensed. See LICENSE for full details.
