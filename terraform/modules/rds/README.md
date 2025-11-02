# RDS PostgreSQL Terraform Module

Production-ready RDS PostgreSQL module with high availability, automated backups, encryption at rest, enhanced monitoring, and CloudWatch alarms. **Uses AWS-managed master password that NEVER appears in Terraform state.**

## Features

- ✅ **AWS Managed Passwords**: Password generated and managed by AWS, never stored in Terraform state (ephemeral)
- ✅ **Multi-AZ Deployment**: Automatic failover for high availability
- ✅ **Automated Backups**: Configurable retention period (up to 35 days)
- ✅ **Encryption at Rest**: KMS encryption for data security
- ✅ **Secrets Management**: Credentials stored in AWS Secrets Manager with KMS encryption
- ✅ **Enhanced Monitoring**: Real-time OS metrics
- ✅ **Performance Insights**: Query performance analysis
- ✅ **CloudWatch Alarms**: Proactive monitoring and alerting
- ✅ **Storage Autoscaling**: Automatic storage expansion
- ✅ **Custom Parameters**: Optimized PostgreSQL configuration
- ✅ **CloudWatch Logs**: Automatic log export
- ✅ **Deletion Protection**: Prevent accidental deletion
- ✅ **Backup Window Control**: Schedule maintenance and backups

## Password Management Strategy

This module uses **AWS RDS Managed Master Password** feature, which provides superior security:

### How It Works

1. **Password Generation**: AWS generates a secure random password (never visible to Terraform)
2. **Storage**: Password stored in AWS Secrets Manager, encrypted with KMS
3. **State Protection**: Password NEVER appears in Terraform state file (ephemeral)
4. **Access**: Applications retrieve password from Secrets Manager at runtime
5. **Rotation**: Supports automatic password rotation (optional)

### Security Benefits

- ✅ **No State Exposure**: Password never written to terraform.tfstate
- ✅ **Compliance Ready**: Meets SOC2, PCI-DSS, HIPAA requirements
- ✅ **Audit Trail**: All password access logged in CloudTrail
- ✅ **Encryption**: Password encrypted at rest with KMS
- ✅ **Rotation**: Built-in support for automatic rotation
- ✅ **Least Privilege**: IAM controls who can access password

### Secret Structure

The module creates **two secrets** in Secrets Manager:

1. **AWS-Managed Password Secret** (managed by RDS):
   ```json
   {
     "password": "generated-by-aws-32-chars"
   }
   ```

2. **Connection Details Secret** (managed by Terraform):
   ```json
   {
     "username": "dbadmin",
     "host": "rds-endpoint.region.rds.amazonaws.com",
     "port": 5432,
     "dbname": "appdb",
     "engine": "postgres",
     "masterUserSecretArn": "arn:aws:secretsmanager:...",
     "passwordRetrievalCommand": "aws secretsmanager get-secret-value ..."
   }
   ```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         VPC                                  │
│                                                              │
│  ┌──────────────────┐           ┌──────────────────┐       │
│  │   AZ 1           │           │   AZ 2           │       │
│  │  ┌────────────┐  │           │  ┌────────────┐  │       │
│  │  │  Database  │  │◄─────────►│  │  Database  │  │       │
│  │  │  Subnet    │  │Replication│  │  Subnet    │  │       │
│  │  │            │  │           │  │  (Standby) │  │       │
│  │  │ RDS Primary│  │           │  │            │  │       │
│  │  └────────────┘  │           │  └────────────┘  │       │
│  └──────────────────┘           └──────────────────┘       │
│         │                                                   │
│         │                                                   │
└─────────┼───────────────────────────────────────────────────┘
          │
          ▼
   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
   │   KMS Key    │     │   Secrets    │     │  CloudWatch  │
   │  Encryption  │     │   Manager    │     │    Logs      │
   └──────────────┘     └──────────────┘     └──────────────┘
```

## Usage

### Basic Example

```hcl
module "rds" {
  source = "../../modules/rds"

  name_prefix = "myapp-dev"
  environment = "dev"

  # Network configuration
  subnet_ids             = module.vpc.database_subnet_ids
  vpc_security_group_ids = [module.security.rds_security_group_id]

  # Database configuration
  database_name   = "appdb"
  master_username = "dbadmin"

  # Instance configuration
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  # High availability (disabled for dev)
  multi_az = false

  # Backup configuration
  backup_retention_period = 7
  skip_final_snapshot     = true  # OK for dev

  # Protection (disabled for dev)
  deletion_protection = false

  tags = {
    Project = "MyApp"
    Team    = "DevOps"
  }
}
```

### Production Example

```hcl
module "rds" {
  source = "../../modules/rds"

  name_prefix = "myapp-prod"
  environment = "prod"

  # Network configuration
  subnet_ids             = module.vpc.database_subnet_ids
  vpc_security_group_ids = [module.security.rds_security_group_id]

  # Database configuration
  database_name   = "production_db"
  master_username = "dbadmin"

  # Instance configuration (production-sized)
  instance_class        = "db.r6g.large"
  allocated_storage     = 100
  max_allocated_storage = 1000  # Autoscaling up to 1TB
  storage_type          = "gp3"

  # High availability
  multi_az = true

  # Backup configuration
  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  skip_final_snapshot     = false
  delete_automated_backups = false

  # Monitoring
  enabled_monitoring_interval = 60
  performance_insights_enabled = true
  performance_insights_retention_period = 731  # 2 years
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Protection
  deletion_protection      = true
  auto_minor_version_upgrade = true

  # Parameters
  max_connections = 200
  log_min_duration_statement = 500  # Log queries > 500ms

  custom_parameters = [
    {
      name  = "work_mem"
      value = "16384"  # 16MB
    },
    {
      name  = "maintenance_work_mem"
      value = "2097151"  # ~2GB
    }
  ]

  # CloudWatch Alarms
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]
  alarm_cpu_threshold      = 80
  alarm_free_storage_threshold = 10737418240  # 10GB

  tags = {
    Project     = "MyApp"
    Team        = "DevOps"
    Environment = "Production"
    CostCenter  = "Engineering"
    Compliance  = "HIPAA"
  }
}
```

### Cost-Optimized Development Example

```hcl
module "rds" {
  source = "../../modules/rds"

  name_prefix = "myapp-dev"
  environment = "dev"

  subnet_ids             = module.vpc.database_subnet_ids
  vpc_security_group_ids = [module.security.rds_security_group_id]

  # Minimal instance (Free Tier eligible)
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  # Single AZ (no HA)
  multi_az = false

  # Minimal backups
  backup_retention_period = 1
  skip_final_snapshot     = true

  # Minimal monitoring
  enabled_monitoring_interval = 0  # Disable enhanced monitoring
  performance_insights_enabled = false
  enabled_cloudwatch_logs_exports = []

  # No alarms (optional)
  create_cloudwatch_alarms = false

  # Allow immediate deletion
  deletion_protection = false

  # Share KMS key (if available)
  create_kms_key = false
  kms_key_id     = var.shared_kms_key_arn

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
| random | >= 3.5 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |
| random | >= 3.5 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix for all resource names | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| subnet_ids | List of subnet IDs for DB subnet group | `list(string)` | n/a | yes |
| vpc_security_group_ids | List of security group IDs | `list(string)` | n/a | yes |
| database_name | Name of the database | `string` | `"appdb"` | no |
| master_username | Master username | `string` | `""` (auto-generated) | no |
| port | Database port | `number` | `5432` | no |
| engine_version | PostgreSQL version | `string` | `"15.5"` | no |
| parameter_group_family | Parameter group family | `string` | `"postgres15"` | no |
| instance_class | RDS instance class | `string` | `"db.t3.small"` | no |
| allocated_storage | Allocated storage in GB | `number` | `20` | no |
| max_allocated_storage | Max storage for autoscaling | `number` | `100` | no |
| storage_type | Storage type | `string` | `"gp3"` | no |
| multi_az | Enable Multi-AZ | `bool` | `true` | no |
| backup_retention_period | Backup retention in days | `number` | `7` | no |
| backup_window | Backup window (UTC) | `string` | `"03:00-04:00"` | no |
| maintenance_window | Maintenance window (UTC) | `string` | `"sun:04:00-sun:05:00"` | no |
| skip_final_snapshot | Skip final snapshot | `bool` | `false` | no |
| create_kms_key | Create new KMS key | `bool` | `true` | no |
| enabled_monitoring_interval | Enhanced monitoring interval | `number` | `60` | no |
| performance_insights_enabled | Enable Performance Insights | `bool` | `true` | no |
| deletion_protection | Enable deletion protection | `bool` | `true` | no |
| max_connections | Max database connections | `number` | `100` | no |
| create_cloudwatch_alarms | Create CloudWatch alarms | `bool` | `true` | no |
| alarm_actions | SNS topic ARNs for alarms | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| db_instance_endpoint | Database connection endpoint |
| db_instance_address | Database hostname |
| db_instance_port | Database port |
| db_instance_name | Database name |
| db_secret_arn | Secrets Manager secret ARN |
| db_secret_name | Secrets Manager secret name |
| connection_string | PostgreSQL connection string |

## Accessing Database Credentials

Database credentials are stored in **two separate secrets** in AWS Secrets Manager:

### Method 1: Get Full Connection Details (Recommended for Apps)

```bash
# Get connection details secret ARN from Terraform output
CONNECTION_SECRET_ARN=$(terraform output -raw db_connection_secret_arn)

# Retrieve connection details (host, port, username, etc.)
aws secretsmanager get-secret-value \
  --secret-id $CONNECTION_SECRET_ARN \
  --query SecretString \
  --output text | jq .

# Output:
# {
#   "username": "dbadmin",
#   "host": "myapp-dev-db.abc123.eu-north-1.rds.amazonaws.com",
#   "port": 5432,
#   "dbname": "appdb",
#   "engine": "postgres",
#   "masterUserSecretArn": "arn:aws:secretsmanager:eu-north-1:123456789:secret:rds!...",
#   "passwordRetrievalCommand": "aws secretsmanager get-secret-value ..."
# }

# Get the password from AWS-managed secret
MASTER_SECRET_ARN=$(aws secretsmanager get-secret-value \
  --secret-id $CONNECTION_SECRET_ARN \
  --query SecretString --output text | jq -r .masterUserSecretArn)

PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $MASTER_SECRET_ARN \
  --query SecretString --output text | jq -r .password)

echo "Password: $PASSWORD"
```

### Method 2: Get Password Only (Direct Access)

```bash
# Get AWS-managed password secret ARN from Terraform output
MASTER_SECRET_ARN=$(terraform output -raw master_user_secret_arn)

# Retrieve password
aws secretsmanager get-secret-value \
  --secret-id $MASTER_SECRET_ARN \
  --query SecretString \
  --output text | jq -r .password
```

### Method 3: Using Makefile (Easiest)

```bash
# Get connection details
make db-secret ENV=dev

# Or for just the password
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw master_user_secret_arn) \
  --query SecretString --output text | jq -r .password
```

### Method 4: From Application Code (Python)

```python
import boto3
import json

def get_db_credentials():
    """Retrieve database credentials using AWS Managed Password approach"""
    client = boto3.client('secretsmanager')

    # Step 1: Get connection details
    connection_secret_arn = "arn:aws:secretsmanager:..."  # From Terraform output
    response = client.get_secret_value(SecretId=connection_secret_arn)
    connection_details = json.loads(response['SecretString'])

    # Step 2: Get password from AWS-managed secret
    master_secret_arn = connection_details['masterUserSecretArn']
    password_response = client.get_secret_value(SecretId=master_secret_arn)
    password_data = json.loads(password_response['SecretString'])

    # Step 3: Build connection info
    return {
        'host': connection_details['host'],
        'port': connection_details['port'],
        'database': connection_details['dbname'],
        'username': connection_details['username'],
        'password': password_data['password']
    }

# Usage
creds = get_db_credentials()
conn_string = f"postgresql://{creds['username']}:{creds['password']}@{creds['host']}:{creds['port']}/{creds['database']}"
```

### Method 5: Using Environment Variables (EC2/ECS)
```bash
# Export as environment variables
export DB_SECRET_ARN=$(terraform output -raw db_secret_arn)
aws secretsmanager get-secret-value --secret-id $DB_SECRET_ARN --query SecretString --output text | \
  jq -r 'to_entries|map("export \(.key|ascii_upcase)=\(.value|tostring)")|.[]' > db_env.sh
source db_env.sh
```

## Performance Tuning

### Connection Pooling

Use connection pooling to reduce connection overhead:

```python
# Using SQLAlchemy with connection pooling
from sqlalchemy import create_engine

engine = create_engine(
    connection_string,
    pool_size=20,
    max_overflow=0,
    pool_pre_ping=True,
    pool_recycle=3600
)
```

### Query Optimization

```sql
-- Find slow queries
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Find missing indexes
SELECT schemaname, tablename, attname
FROM pg_stats
WHERE correlation < 0.1
ORDER BY schemaname, tablename;

-- Check table bloat
SELECT schemaname, tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Parameter Recommendations

Based on instance size:

#### db.t3.micro (1GB RAM)
```hcl
max_connections = 50
shared_buffers = 32768  # 256MB
work_mem = 2048         # 2MB
```

#### db.t3.small (2GB RAM)
```hcl
max_connections = 100
shared_buffers = 65536  # 512MB
work_mem = 4096         # 4MB
```

#### db.r6g.large (16GB RAM)
```hcl
max_connections = 500
shared_buffers = 524288  # 4GB
work_mem = 16384         # 16MB
maintenance_work_mem = 2097151  # 2GB
```

## Cost Optimization

### Estimated Monthly Costs (eu-north-1)

| Configuration | Instance | Storage | Multi-AZ | Est. Cost |
|---------------|----------|---------|----------|-----------|
| Dev (Minimal) | db.t3.micro | 20GB gp3 | No | ~$15 |
| Dev (Standard) | db.t3.small | 50GB gp3 | No | ~$30 |
| Prod (Small) | db.t3.small | 100GB gp3 | Yes | ~$60 |
| Prod (Medium) | db.r6g.large | 500GB gp3 | Yes | ~$400 |
| Prod (Large) | db.r6g.xlarge | 1TB gp3 | Yes | ~$800 |

### Cost Savings Tips

1. **Use Reserved Instances** for production (up to 60% savings)
   ```bash
   aws rds describe-reserved-db-instances-offerings \
     --db-instance-class db.r6g.large
   ```

2. **Right-size instances** based on actual usage
   ```bash
   # Check CPU utilization
   aws cloudwatch get-metric-statistics \
     --namespace AWS/RDS \
     --metric-name CPUUtilization \
     --dimensions Name=DBInstanceIdentifier,Value=mydb \
     --statistics Average \
     --start-time 2024-01-01T00:00:00Z \
     --end-time 2024-01-31T23:59:59Z \
     --period 3600
   ```

3. **Use Storage Autoscaling** to avoid over-provisioning

4. **Disable Multi-AZ** for non-production environments

5. **Reduce backup retention** for dev/test (1-7 days instead of 30)

6. **Use Graviton instances** (r6g) for better price/performance

## Security Best Practices

### ✅ Implemented

1. **Encryption at rest** with KMS
2. **Encryption in transit** (SSL/TLS enforced)
3. **Secrets in AWS Secrets Manager**
4. **Private subnets only** (no public access)
5. **Security group restrictions**
6. **IAM authentication** (optional, can be enabled)
7. **CloudWatch logging** enabled
8. **Deletion protection** enabled for production

### 🔒 Additional Recommendations

1. **Enable SSL connections**:
   ```sql
   ALTER SYSTEM SET ssl = on;
   ```

2. **Use IAM database authentication**:
   ```hcl
   iam_database_authentication_enabled = true
   ```

3. **Enable automatic backups to S3**:
   ```bash
   aws rds create-db-snapshot \
     --db-instance-identifier mydb \
     --db-snapshot-identifier mydb-snapshot
   ```

4. **Rotate credentials regularly**:
   ```bash
   aws secretsmanager rotate-secret \
     --secret-id myapp-db-credentials
   ```

5. **Use AWS Config rules** to check compliance:
   ```bash
   aws configservice put-config-rule \
     --config-rule file://rds-encryption-enabled.json
   ```

## Disaster Recovery

### Automated Backups

Automated backups are enabled by default with 7-day retention. To restore:

```bash
# List available backups
aws rds describe-db-snapshots \
  --db-instance-identifier myapp-prod-db

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier myapp-prod-db-restored \
  --db-snapshot-identifier rds:myapp-prod-db-2024-01-15-03-00
```

### Point-in-Time Recovery

Restore to any point within the backup retention period:

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier myapp-prod-db \
  --target-db-instance-identifier myapp-prod-db-pitr \
  --restore-time 2024-01-15T12:00:00Z
```

### Cross-Region Backups

For disaster recovery, enable cross-region snapshots:

```bash
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier arn:aws:rds:eu-north-1:123456789:snapshot:myapp-snapshot \
  --target-db-snapshot-identifier myapp-snapshot-dr \
  --region us-west-2
```

## Monitoring

### Key Metrics to Monitor

1. **CPUUtilization**: Should be < 80%
2. **FreeableMemory**: Should be > 256MB
3. **FreeStorageSpace**: Should be > 10GB
4. **DatabaseConnections**: Should be < 80% of max_connections
5. **ReadLatency / WriteLatency**: Should be < 10ms
6. **ReplicaLag**: Should be < 1000ms (if using read replicas)

### View CloudWatch Metrics

```bash
# CPU Utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=myapp-prod-db \
  --statistics Average \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300

# Database Connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=myapp-prod-db \
  --statistics Average,Maximum \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300
```

## Troubleshooting

### Issue: Cannot connect to database

**Check 1**: Security group rules
```bash
aws ec2 describe-security-groups --group-ids sg-xxx
```

**Check 2**: Database status
```bash
aws rds describe-db-instances --db-instance-identifier myapp-prod-db \
  --query 'DBInstances[0].DBInstanceStatus'
```

**Check 3**: Connection from EC2
```bash
# From application instance
psql -h myapp-prod-db.xxxxx.eu-north-1.rds.amazonaws.com -U dbadmin -d appdb
```

### Issue: High CPU utilization

**Check slow queries**:
```sql
SELECT pid, now() - query_start as duration, query
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;
```

**Kill long-running query**:
```sql
SELECT pg_terminate_backend(pid);
```

### Issue: Storage full

**Check storage usage**:
```sql
SELECT pg_size_pretty(pg_database_size('appdb'));
```

**Find largest tables**:
```sql
SELECT schemaname, tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
```

## Migration

### From Existing RDS

```bash
# 1. Create snapshot of source
aws rds create-db-snapshot \
  --db-instance-identifier source-db \
  --db-snapshot-identifier migration-snapshot

# 2. Deploy this module
terraform apply

# 3. Restore data from snapshot
# (This module creates a new instance, you'll need to migrate data manually)
pg_dump -h source-db.amazonaws.com -U user dbname | \
  psql -h new-db.amazonaws.com -U user dbname
```

### To RDS from Self-Managed PostgreSQL

```bash
# Using pg_dump and pg_restore
pg_dump -h old-server -U user -Fc dbname > dump.sql
pg_restore -h new-rds-instance.amazonaws.com -U user -d dbname dump.sql
```

## Authors

Created and maintained by DevOps Team

## License

MIT Licensed. See LICENSE for full details.
