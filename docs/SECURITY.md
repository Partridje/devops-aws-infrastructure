# Security Documentation

## Table of Contents

- [Overview](#overview)
- [Security Principles](#security-principles)
- [Network Security](#network-security)
- [Identity and Access Management](#identity-and-access-management)
- [Data Security](#data-security)
- [Application Security](#application-security)
- [Infrastructure Security](#infrastructure-security)
- [Monitoring and Detection](#monitoring-and-detection)
- [Compliance Considerations](#compliance-considerations)
- [Threat Model](#threat-model)
- [Incident Response](#incident-response)
- [Security Testing](#security-testing)
- [Security Checklist](#security-checklist)

## Overview

This document outlines the security architecture, controls, and best practices implemented in this DevOps infrastructure project. The infrastructure follows a defense-in-depth approach with multiple layers of security controls.

### Security Objectives

- **Confidentiality**: Protect sensitive data through encryption and access controls
- **Integrity**: Ensure data accuracy and prevent unauthorized modifications
- **Availability**: Maintain system uptime through redundancy and fault tolerance
- **Auditability**: Log all security-relevant events for compliance and investigation

## Security Principles

### Defense in Depth

Multiple layers of security controls protect against various attack vectors:

1. **Network Layer**: VPC isolation, security groups, NACLs
2. **Infrastructure Layer**: IMDSv2, encrypted storage, hardened AMIs
3. **Application Layer**: Input validation, secure coding practices, dependency scanning
4. **Data Layer**: Encryption at rest and in transit, secrets management
5. **Identity Layer**: IAM roles, least privilege, MFA enforcement

### Principle of Least Privilege

Every component has the minimum permissions required:

- IAM roles grant only necessary permissions
- Security groups allow only required ports and sources
- Database users have limited grants
- Application runs as non-root user

### Security by Default

Secure defaults are configured across all components:

- Encryption enabled by default (RDS, EBS, S3)
- Public access blocked by default
- IMDSv2 required for all EC2 instances
- HTTPS enforced for external communication
- Automated security patches enabled

## Network Security

### VPC Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         VPC (10.0.0.0/16)                   │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Public AZ1  │  │  Public AZ2  │  │  Public AZ3  │      │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │      │
│  │ │   ALB    │ │  │ │   ALB    │ │  │ │   ALB    │ │      │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │      │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │      │
│  │ │NAT GW/EIP│ │  │ │NAT GW/EIP│ │  │ │NAT GW/EIP│ │      │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         ▲                 ▲                 ▲               │
│         │  Internet Gateway (IGW)           │               │
│         └─────────────────┴─────────────────┘               │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Private AZ1  │  │ Private AZ2  │  │ Private AZ3  │      │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │      │
│  │ │  EC2 App │ │  │ │  EC2 App │ │  │ │  EC2 App │ │      │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                 │                 │               │
│         ▼                 ▼                 ▼               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │Database AZ1  │  │Database AZ2  │  │Database AZ3  │      │
│  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │      │
│  │ │    RDS   │ │  │ │RDS Standby│ │  │ │RDS Standby│ │     │
│  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### Network Segmentation

**Public Subnets (DMZ)**:
- Only ALB instances exposed to internet
- NAT Gateways for outbound traffic
- CIDR: 10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24

**Private Subnets (Application Tier)**:
- EC2 application instances
- No direct internet access (outbound via NAT)
- CIDR: 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24

**Database Subnets (Data Tier)**:
- Isolated RDS instances
- No internet access (inbound or outbound)
- CIDR: 10.0.20.0/24, 10.0.21.0/24, 10.0.22.0/24

### Security Groups

#### ALB Security Group

```hcl
Inbound:
  - HTTP (80) from 0.0.0.0/0
  - HTTPS (443) from 0.0.0.0/0

Outbound:
  - Application Port (5001) to Application Security Group
```

**Rationale**: ALB is internet-facing and must accept public traffic, but can only forward to application tier.

#### Application Security Group

```hcl
Inbound:
  - Application Port (5001) from ALB Security Group only
  - No SSH access (use SSM Session Manager)

Outbound:
  - PostgreSQL (5432) to RDS Security Group
  - HTTPS (443) to 0.0.0.0/0 (for AWS API calls, package updates)
  - HTTP (80) to 0.0.0.0/0 (for package repositories)
```

**Rationale**: Application instances only accept traffic from ALB and can only communicate with RDS and AWS services.

#### RDS Security Group

```hcl
Inbound:
  - PostgreSQL (5432) from Application Security Group only

Outbound:
  - None required (database doesn't initiate connections)
```

**Rationale**: Database is completely isolated and only accessible from application tier.

#### VPC Endpoints Security Group

```hcl
Inbound:
  - HTTPS (443) from VPC CIDR (10.0.0.0/16)

Outbound:
  - Not applicable (managed by AWS)
```

**Rationale**: VPC endpoints allow private AWS service access without internet gateway.

### Network Flow Logs

VPC Flow Logs capture all network traffic for security analysis:

```hcl
resource "aws_flow_log" "vpc_flow_log" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"  # ACCEPT, REJECT, or ALL
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-logs"
  }
}
```

**Use Cases**:
- Detect unauthorized access attempts
- Analyze traffic patterns
- Troubleshoot connectivity issues
- Meet compliance requirements

### VPC Endpoints

Gateway endpoints for AWS services eliminate internet exposure:

- **S3 Endpoint**: Access S3 buckets without NAT Gateway
- **DynamoDB Endpoint**: Access DynamoDB tables without NAT Gateway

**Benefits**:
- No data transfer costs
- Traffic stays within AWS network
- Reduced attack surface

## Identity and Access Management

### IAM Roles

#### EC2 Instance Role

```hcl
Permissions:
  - AmazonSSMManagedInstanceCore (SSM Session Manager)
  - SecretsManagerReadWrite (retrieve DB credentials)
  - CloudWatchAgentServerPolicy (send metrics/logs)
  - AmazonEC2ContainerRegistryReadOnly (pull Docker images)
  - Custom inline policy (minimal S3 access if needed)
```

**Key Points**:
- No long-term credentials stored on instances
- Temporary credentials rotated automatically by AWS
- Instance profile attached to launch template

#### GitHub Actions OIDC Role

```hcl
Trust Policy:
  - GitHub OIDC provider (token.actions.githubusercontent.com)
  - Repository condition: "repo:YOUR_ORG/YOUR_REPO:*"
  - Branch condition: "ref:refs/heads/main"

Permissions:
  - AdministratorAccess (for demo - RESTRICT IN PRODUCTION)
```

**Production Recommendation**:
```hcl
# Replace AdministratorAccess with specific permissions
Permissions:
  - EC2 describe/create/modify/delete for managed resources
  - ECS/ECR full access for application deployment
  - RDS describe/modify for database management
  - S3 access to Terraform state bucket
  - DynamoDB access to state lock table
  - CloudWatch read/write for logs and metrics
  - IAM PassRole for creating resources with roles
```

#### RDS Enhanced Monitoring Role

```hcl
Trust Policy:
  - monitoring.rds.amazonaws.com

Permissions:
  - AmazonRDSEnhancedMonitoringRole
```

### MFA Enforcement

**Recommendation**: Enforce MFA for all IAM users (if using IAM users):

```hcl
resource "aws_iam_policy" "require_mfa" {
  name = "RequireMFA"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyAllExceptListedIfNoMFA"
        Effect = "Deny"
        NotAction = [
          "iam:CreateVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:GetUser",
          "iam:ListMFADevices",
          "iam:ListVirtualMFADevices",
          "iam:ResyncMFADevice",
          "sts:GetSessionToken"
        ]
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
        }
      }
    ]
  })
}
```

### Access Management Best Practices

1. **Use IAM Roles**, not IAM users, wherever possible
2. **Enable CloudTrail** for all API call auditing
3. **Rotate credentials** regularly (AWS Secrets Manager handles DB credentials)
4. **Use AWS Organizations** for multi-account governance
5. **Implement SCPs** (Service Control Policies) for organization-wide guardrails

## Data Security

### Encryption at Rest

#### RDS Encryption

```hcl
resource "aws_db_instance" "main" {
  storage_encrypted   = true
  kms_key_id         = aws_kms_key.rds.arn

  # KMS key with automatic rotation
  resource "aws_kms_key" "rds" {
    enable_key_rotation = true
    deletion_window_in_days = 30
  }
}
```

**Key Management**:
- Customer-managed KMS key (not AWS-managed)
- Automatic key rotation enabled annually
- 30-day deletion window for recovery
- CloudTrail logs all key usage

#### EBS Encryption

```hcl
resource "aws_launch_template" "main" {
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted   = true
      kms_key_id  = var.ebs_kms_key_id  # Optional: use specific key
      volume_type = "gp3"
      volume_size = 30
    }
  }
}
```

#### S3 Encryption (Terraform State)

```bash
# setup-terraform-backend.sh
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

**State File Security**:
- Server-side encryption enabled
- Versioning enabled for state history
- Bucket policy denies unencrypted uploads
- Access restricted to Terraform OIDC role

### Encryption in Transit

#### Application to Database

```python
# PostgreSQL connection with SSL/TLS
db_config = {
    'host': db_host,
    'port': 5432,
    'database': db_name,
    'user': db_user,
    'password': db_password,
    'sslmode': 'require',  # Enforce SSL/TLS
    'sslrootcert': '/etc/ssl/certs/rds-ca-2019-root.pem'
}
```

**RDS Parameter Group**:
```hcl
resource "aws_db_parameter_group" "main" {
  parameter {
    name  = "rds.force_ssl"
    value = "1"  # Enforce SSL for all connections
  }
}
```

#### Client to ALB

```hcl
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"  # TLS 1.2+
  certificate_arn   = var.ssl_certificate_arn
}
```

**SSL/TLS Policies**:
- Minimum TLS 1.2 (PCI-DSS requirement)
- Strong cipher suites only
- Perfect Forward Secrecy (PFS) enabled

#### ALB to Application

Currently HTTP (internal VPC traffic):
```hcl
resource "aws_lb_target_group" "main" {
  port     = 5001
  protocol = "HTTP"
}
```

**Enhancement Recommendation**: Use HTTPS for internal traffic
```hcl
# Generate internal certificates with ACM Private CA
resource "aws_lb_target_group" "main" {
  port     = 443
  protocol = "HTTPS"

  health_check {
    protocol = "HTTPS"
  }
}
```

### Secrets Management

#### AWS Secrets Manager

Database credentials stored in Secrets Manager, not environment variables:

```hcl
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}-${var.environment}-db-credentials"
  recovery_window_in_days = 30

  # Optional: Enable automatic rotation
  # rotation_lambda_arn = aws_lambda_function.rotate_secret.arn
  # rotation_rules {
  #   automatically_after_days = 30
  # }
}
```

Application retrieves credentials at runtime:

```python
def _get_db_credentials_from_secrets_manager(self):
    try:
        client = boto3.client('secretsmanager', region_name=Config.AWS_REGION)
        response = client.get_secret_value(SecretId=Config.DB_SECRET_ARN)

        secret = json.loads(response['SecretString'])
        return {
            'host': secret['host'],
            'database': secret['dbname'],
            'user': secret['username'],
            'password': secret['password']
        }
    except Exception as e:
        logger.warning(f"Failed to retrieve credentials from Secrets Manager: {e}")
        return None
```

**Benefits**:
- Centralized secret storage
- Audit trail of secret access (CloudTrail)
- Automatic rotation support (future enhancement)
- No secrets in code or environment variables
- Encryption at rest with KMS

### Data Backup and Recovery

#### RDS Automated Backups

```hcl
resource "aws_db_instance" "main" {
  backup_retention_period = var.backup_retention_days  # 30 for prod, 1 for dev
  backup_window          = "03:00-04:00"  # UTC
  maintenance_window     = "sun:04:00-sun:05:00"  # UTC

  copy_tags_to_snapshot  = true
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
}
```

**Backup Strategy**:
- Automated daily backups during maintenance window
- Point-in-time recovery (PITR) for last N days
- Final snapshot on deletion (production)
- Cross-region backup replication (future enhancement)

#### Terraform State Backups

```bash
# S3 versioning for state file history
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled
```

**Recovery Process**:
1. List versions: `aws s3api list-object-versions --bucket BUCKET --prefix terraform.tfstate`
2. Restore version: `aws s3api get-object --bucket BUCKET --key terraform.tfstate --version-id VERSION_ID state-backup.tfstate`

## Application Security

### Container Security

#### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Builder (includes build tools)
FROM python:3.11-slim as builder
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev
RUN python -m venv /opt/venv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 2: Runtime (minimal attack surface)
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN groupadd -r appuser && useradd -r -g appuser -u 1000 appuser
USER appuser

COPY --from=builder /opt/venv /opt/venv
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:5001/health || exit 1
```

**Security Features**:
- Multi-stage build reduces image size and attack surface
- Non-root user (UID 1000) prevents privilege escalation
- Minimal runtime dependencies (only libpq5, curl, ca-certificates)
- Health checks for rapid failure detection
- No secrets baked into image layers

#### Image Scanning

Trivy vulnerability scanner in CI/CD:

```yaml
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ steps.meta.outputs.image }}
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'
```

**Scan Triggers**:
- Every Docker build in CI
- Before pushing to ECR
- Weekly scheduled scans of production images

### Dependency Management

#### Python Dependencies

```txt
# requirements.txt with pinned versions
Flask==3.0.0
psycopg2-binary==2.9.9
boto3==1.34.0
gunicorn==21.2.0
```

**Security Practices**:
- Pin exact versions (not `>=`)
- Use `pip-audit` to scan for vulnerabilities
- Regular dependency updates (monthly)
- Review changelogs before updating

#### Automated Scanning

Pre-commit hook for dependency scanning:

```yaml
# .pre-commit-config.yaml
- repo: https://github.com/trufflesecurity/trufflehog
  rev: v3.63.0
  hooks:
    - id: trufflehog
      name: TruffleHog (secrets scanning)
```

### Input Validation

```python
@app.route('/api/items', methods=['POST'])
def create_item():
    # Validate Content-Type
    if not request.is_json:
        return jsonify({'error': 'Content-Type must be application/json'}), 400

    data = request.get_json()

    # Validate required fields
    if not data or 'name' not in data:
        return jsonify({'error': 'Missing required field: name'}), 400

    # Sanitize input
    name = str(data['name']).strip()[:255]  # Limit length
    description = str(data.get('description', '')).strip()[:1000]

    # Parameterized query (prevents SQL injection)
    cursor.execute(
        "INSERT INTO items (name, description) VALUES (%s, %s) RETURNING id",
        (name, description)
    )
```

**SQL Injection Prevention**:
- Always use parameterized queries
- Never concatenate user input into SQL
- Use ORM when possible (SQLAlchemy)

### OWASP Top 10 Mitigation

| Risk | Mitigation |
|------|------------|
| **A01: Broken Access Control** | IAM roles, security groups, least privilege |
| **A02: Cryptographic Failures** | TLS 1.2+, KMS encryption, Secrets Manager |
| **A03: Injection** | Parameterized queries, input validation |
| **A04: Insecure Design** | Defense in depth, security reviews |
| **A05: Security Misconfiguration** | IaC, automated scanning, hardened defaults |
| **A06: Vulnerable Components** | Dependency scanning, regular updates |
| **A07: Authentication Failures** | IAM, MFA, session management |
| **A08: Software/Data Integrity** | Image signing, checksums, SBOM |
| **A09: Logging Failures** | CloudWatch, structured logging, alerting |
| **A10: SSRF** | VPC isolation, egress filtering, IMDSv2 |

## Infrastructure Security

### EC2 Hardening

#### Instance Metadata Service v2 (IMDSv2)

```hcl
resource "aws_launch_template" "main" {
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # Enforces IMDSv2
    http_put_response_hop_limit = 1           # Prevents SSRF
    instance_metadata_tags      = "enabled"
  }
}
```

**IMDSv2 Benefits**:
- Prevents SSRF attacks (requires PUT request with token)
- Session-oriented (token has TTL)
- Hop limit prevents container escape

#### Automated Patching

```bash
# user_data.sh
dnf update -y
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Enable automatic security updates
dnf install -y dnf-automatic
systemctl enable --now dnf-automatic.timer
```

**Patch Management**:
- Automated OS updates via dnf-automatic
- ASG instance refresh for zero-downtime patching
- AWS Systems Manager Patch Manager (future enhancement)

### No SSH Access

Traditional SSH is disabled. Access via **AWS Systems Manager Session Manager**:

```bash
# Start interactive session
aws ssm start-session --target i-1234567890abcdef0

# Run command across fleet
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Environment,Values=prod" \
  --parameters 'commands=["uptime","df -h"]'
```

**Benefits**:
- No SSH keys to manage
- No bastion hosts to secure
- All sessions logged to CloudWatch
- MFA enforcement possible
- No open port 22

### Auto Scaling Security

```hcl
resource "aws_autoscaling_group" "main" {
  # Rolling updates
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type         = "ELB"
  health_check_grace_period = 300

  # Prevent accidental instance termination during deployment
  protect_from_scale_in = var.environment == "prod" ? true : false

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90  # Always maintain 90% capacity
    }
  }
}
```

### Resource Deletion Protection

Production resources protected from accidental deletion:

```hcl
# RDS
resource "aws_db_instance" "main" {
  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment == "prod" ? false : true
}

# ALB
resource "aws_lb" "main" {
  enable_deletion_protection = var.environment == "prod" ? true : false
}
```

## Monitoring and Detection

### CloudWatch Alarms

#### Critical Alarms

```hcl
# Unhealthy target hosts
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-${var.environment}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  threshold           = "0"
  alarm_actions       = [var.sns_topic_arn]
}

# High 5xx error rate
resource "aws_cloudwatch_metric_alarm" "http_5xx_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-high-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  threshold           = "10"
  alarm_actions       = [var.sns_topic_arn]
}

# Database CPU
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-db-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  threshold           = "80"
  alarm_actions       = [var.sns_topic_arn]
}
```

### Security Monitoring

#### GuardDuty (Recommendation)

```hcl
# Enable AWS GuardDuty for threat detection
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
  }
}

# Export findings to SNS
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-findings"
  description = "Capture GuardDuty findings"

  event_pattern = jsonencode({
    source = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}
```

**GuardDuty Detects**:
- Compromised EC2 instances (Bitcoin mining, backdoors)
- Compromised credentials (unusual API calls)
- Reconnaissance attacks (port scanning)
- Data exfiltration attempts

#### CloudTrail

Enable CloudTrail for all API call logging:

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-${var.environment}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${aws_s3_bucket.app_data.id}/*"]
    }
  }
}
```

**CloudTrail Use Cases**:
- Who made what API call when?
- Unauthorized access attempts
- Compliance audit trail
- Incident investigation

### Log Aggregation

```hcl
# Centralized log group
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/ec2/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_id
}

# Metric filters for security events
resource "aws_cloudwatch_log_metric_filter" "failed_login" {
  name           = "FailedLoginAttempts"
  log_group_name = aws_cloudwatch_log_group.application.name

  pattern = "[time, request_id, level=ERROR, msg=\"*authentication failed*\"]"

  metric_transformation {
    name      = "FailedLoginAttempts"
    namespace = "${var.project_name}/${var.environment}"
    value     = "1"
  }
}
```

## Compliance Considerations

### CIS AWS Foundations Benchmark

| Control | Implementation |
|---------|----------------|
| **1.2 - MFA for IAM users** | Enforce via IAM policy |
| **1.3 - Credentials unused 90 days** | IAM credential report, automated deactivation |
| **1.4 - Access keys rotated 90 days** | Use IAM roles instead |
| **2.1 - CloudTrail enabled** | Enabled across all regions |
| **2.2 - CloudTrail log validation** | `enable_log_file_validation = true` |
| **2.3 - S3 bucket access logging** | Enabled for state bucket |
| **2.6 - S3 bucket public access** | Block public access |
| **2.7 - CloudTrail encrypted** | KMS encryption enabled |
| **3.1 - VPC flow logs enabled** | Enabled, sent to CloudWatch |
| **3.2 - Default security groups** | Restrict default SG to deny all |
| **4.1 - Security groups - no 0.0.0.0/0 ingress** | Only ALB SG has public access |
| **4.2 - SSH restricted** | SSH disabled, use SSM |
| **4.3 - RDP restricted** | No Windows instances |

### PCI-DSS Considerations

If handling payment card data:

| Requirement | Implementation |
|-------------|----------------|
| **Req 1: Firewalls** | Security groups, NACLs |
| **Req 2: Secure configurations** | Hardened AMIs, config management |
| **Req 3: Protect cardholder data** | KMS encryption, tokenization |
| **Req 4: Encrypt transmission** | TLS 1.2+, no SSLv3/TLS1.0/1.1 |
| **Req 6: Secure development** | Code reviews, SAST/DAST scanning |
| **Req 8: Access control** | IAM, MFA, unique IDs |
| **Req 10: Logging** | CloudWatch, CloudTrail, retention |
| **Req 11: Security testing** | Trivy, Checkov, tfsec, penetration tests |

### HIPAA Considerations

If handling PHI (Protected Health Information):

- **BAA Required**: Sign AWS Business Associate Agreement
- **Encryption**: All data encrypted at rest and in transit (✅ implemented)
- **Access Controls**: Role-based access with audit trail (✅ implemented)
- **Audit Logs**: Retain for 6+ years (adjust CloudWatch retention)
- **Disaster Recovery**: Documented backup/restore procedures
- **Risk Analysis**: Annual security risk assessment

### SOC 2 Type II

For SOC 2 compliance:

- **Security**: Implemented (defense in depth, encryption, monitoring)
- **Availability**: Implemented (Multi-AZ, Auto Scaling, health checks)
- **Processing Integrity**: Use checksums, validate inputs
- **Confidentiality**: Encryption, access controls, Secrets Manager
- **Privacy**: Data classification, retention policies, DPO

## Threat Model

### Assets

1. **Application Data**: Customer records in RDS PostgreSQL
2. **Credentials**: Database passwords, API keys in Secrets Manager
3. **Infrastructure**: EC2 instances, RDS databases, ALB
4. **Terraform State**: Contains sensitive output values

### Threat Actors

1. **External Attackers**: Internet-based adversaries
2. **Malicious Insiders**: Rogue employees with AWS access
3. **Supply Chain Attacks**: Compromised dependencies or Docker images
4. **Automated Attacks**: Bots, scanners, worms

### Attack Vectors

#### 1. Internet-Facing ALB

**Threat**: DDoS, web application attacks, credential stuffing

**Mitigations**:
- AWS Shield Standard (automatic DDoS protection)
- Rate limiting via WAF (future enhancement)
- Connection limits on ALB
- Health checks prevent overload

**Future Enhancement**:
```hcl
# AWS WAF for advanced protection
resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project_name}-${var.environment}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitRule"
    priority = 1

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    action {
      block {}
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
  }
}
```

#### 2. Application Layer (EC2)

**Threat**: Remote code execution, SSRF, container escape

**Mitigations**:
- Input validation and parameterized queries
- IMDSv2 prevents SSRF to metadata service
- Non-root container user prevents privilege escalation
- Security groups limit lateral movement
- No SSH access (SSM only)

#### 3. Data Layer (RDS)

**Threat**: SQL injection, data exfiltration, unauthorized access

**Mitigations**:
- Database in isolated subnet (no internet)
- Security group allows only app tier
- Encryption at rest with KMS
- SSL/TLS enforced for connections
- Automated backups for recovery

#### 4. Supply Chain

**Threat**: Compromised Python packages, malicious Docker base images

**Mitigations**:
- Pin exact dependency versions
- Trivy scanning for known vulnerabilities
- Use official Python base images from Docker Hub
- Verify image signatures (future: Docker Content Trust)
- Private ECR repository for production images

#### 5. Insider Threats

**Threat**: Malicious employee with AWS console/CLI access

**Mitigations**:
- Least privilege IAM roles
- CloudTrail logs all actions
- MFA required for sensitive operations
- No long-term access keys (use temporary credentials)
- Deletion protection on production resources

### Attack Scenarios

#### Scenario 1: Compromised EC2 Instance

**Attack**: Attacker exploits application vulnerability and gains shell access

**Kill Chain**:
1. Exploit vulnerability → Execute code
2. Attempt privilege escalation → **BLOCKED** (non-root user)
3. Attempt to access metadata service → **BLOCKED** (IMDSv2 required)
4. Attempt lateral movement to RDS → **BLOCKED** (security group, TLS required)
5. Attempt to exfiltrate via internet → **DETECTED** (VPC Flow Logs, GuardDuty)

**Response**:
1. CloudWatch alarm triggers on anomalous behavior
2. Isolate instance (modify security group to deny all)
3. Snapshot EBS volume for forensics
4. Terminate instance (ASG replaces with clean instance)
5. Review CloudWatch Logs and CloudTrail for root cause

#### Scenario 2: Stolen AWS Credentials

**Attack**: GitHub Actions OIDC role credentials stolen

**Kill Chain**:
1. Attacker uses stolen credentials
2. Attempts to access Secrets Manager → **LOGGED** (CloudTrail)
3. Attempts to modify security groups → **LOGGED** (CloudTrail)
4. Attempts to create backdoor IAM user → **ALERTED** (CloudWatch Events)

**Response**:
1. Revoke temporary credentials (expire in 1 hour)
2. Modify trust policy to restrict OIDC role
3. Review CloudTrail for unauthorized actions
4. Rollback any infrastructure changes via Terraform

#### Scenario 3: SQL Injection Attack

**Attack**: Attacker sends malicious SQL in API request

**Defense**:
```python
# VULNERABLE (don't do this)
cursor.execute(f"SELECT * FROM items WHERE name = '{user_input}'")

# SECURE (parameterized query)
cursor.execute("SELECT * FROM items WHERE name = %s", (user_input,))
```

**Additional Defenses**:
- Input validation (max length, character whitelist)
- Web Application Firewall (future enhancement)
- Database monitoring for anomalous queries

## Incident Response

### Incident Response Plan

#### 1. Preparation

- Maintain updated contact list (on-call rotation)
- Document runbooks for common scenarios
- Test incident response procedures quarterly
- Ensure all team members have necessary AWS access

#### 2. Detection

**Automated Detection**:
- CloudWatch Alarms → SNS → Email/PagerDuty
- GuardDuty findings → EventBridge → Lambda → Slack
- Anomaly detection via CloudWatch Insights

**Manual Detection**:
- Customer reports
- Penetration test findings
- Security researcher disclosure

#### 3. Analysis

```bash
# Check CloudTrail for suspicious API calls
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --start-time 2024-01-01T00:00:00Z \
  --max-results 50

# Query CloudWatch Logs
aws logs start-query \
  --log-group-name /aws/ec2/demo-flask-app-prod \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, @message | filter level = "ERROR" | sort @timestamp desc | limit 100'

# Check GuardDuty findings
aws guardduty list-findings --detector-id <detector-id>
```

#### 4. Containment

**Immediate Actions**:
```bash
# Isolate compromised EC2 instance
aws ec2 modify-instance-attribute \
  --instance-id i-1234567890abcdef0 \
  --groups sg-quarantine

# Rotate credentials
aws secretsmanager rotate-secret \
  --secret-id demo-flask-app-prod-db-credentials

# Revoke IAM session
aws sts revoke-session \
  --role-session-name <session-name>
```

#### 5. Eradication

- Terminate compromised instances (ASG will replace)
- Patch vulnerable application code
- Update security group rules
- Review and update IAM policies

#### 6. Recovery

```bash
# Restore from backup if needed
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier prod-db \
  --target-db-instance-identifier prod-db-restored \
  --restore-time 2024-01-01T12:00:00Z

# Deploy fixed application version
terraform apply -var="app_version=v1.2.3-patched"
```

#### 7. Lessons Learned

- Post-incident review meeting within 72 hours
- Document timeline of events
- Update runbooks and procedures
- Implement preventive controls
- Share learnings with team

### Incident Severity Levels

| Severity | Definition | Response Time | Examples |
|----------|------------|---------------|----------|
| **P0 - Critical** | Service down, data breach | 15 minutes | RDS inaccessible, credentials leaked |
| **P1 - High** | Degraded service, active attack | 1 hour | High error rate, brute force detected |
| **P2 - Medium** | Limited impact, potential threat | 4 hours | Single instance compromised, CVE published |
| **P3 - Low** | Minimal impact, informational | 1 business day | Configuration drift, expired certificate warning |

### Communication Templates

#### Security Incident Notification

```
Subject: [SECURITY INCIDENT] Brief description

SEVERITY: [P0/P1/P2/P3]
STATUS: [Investigating/Contained/Resolved]
AFFECTED SYSTEMS: [List systems/services]
CUSTOMER IMPACT: [Yes/No - describe]

SUMMARY:
[Brief description of incident]

TIMELINE:
- HH:MM - Incident detected
- HH:MM - Incident response initiated
- HH:MM - Systems contained

ACTIONS TAKEN:
1. [Action 1]
2. [Action 2]

NEXT STEPS:
- [Next step 1]
- [Next step 2]

CONTACT:
Incident Commander: [Name]
```

## Security Testing

### Continuous Security Testing

#### Static Application Security Testing (SAST)

```yaml
# .github/workflows/tests.yml
- name: Run Bandit (Python SAST)
  run: |
    pip install bandit
    bandit -r app/src/ -f json -o bandit-report.json
```

#### Infrastructure Security Testing

```yaml
# Terraform security scanning
- name: Run Checkov
  uses: bridgecrewio/checkov-action@master
  with:
    directory: terraform/
    framework: terraform

- name: Run tfsec
  uses: aquasecurity/tfsec-action@v1.0.3
  with:
    working_directory: terraform/
```

#### Container Security Testing

```yaml
# Docker image scanning
- name: Run Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'demo-flask-app:latest'
    format: 'sarif'
    severity: 'CRITICAL,HIGH'
```

### Penetration Testing

**Recommendation**: Annual third-party penetration testing

**AWS Requirements**:
- Submit request via https://aws.amazon.com/security/penetration-testing/
- Allowed targets: EC2, ALB, RDS, Lambda
- Prohibited: DoS, flooding, resource exhaustion

**Testing Scope**:
- External penetration test (internet-facing ALB)
- Internal penetration test (assume compromised instance)
- Application security assessment (OWASP testing)
- Social engineering (phishing simulations)

### Vulnerability Management

**Process**:
1. **Identify**: Trivy, GuardDuty, AWS Security Hub
2. **Prioritize**: CVSS score, exploitability, asset criticality
3. **Remediate**: Patch within SLA (critical: 7 days, high: 30 days)
4. **Verify**: Re-scan after patching

**Remediation SLAs**:
| Severity | SLA | Example |
|----------|-----|---------|
| Critical (CVSS 9.0-10.0) | 7 days | Remote code execution |
| High (CVSS 7.0-8.9) | 30 days | SQL injection |
| Medium (CVSS 4.0-6.9) | 90 days | XSS, information disclosure |
| Low (CVSS 0.1-3.9) | Best effort | Informational findings |

## Security Checklist

### Pre-Deployment Checklist

- [ ] All Terraform variables reviewed (no hardcoded secrets)
- [ ] Security groups follow least privilege
- [ ] Encryption enabled (RDS, EBS, S3)
- [ ] IMDSv2 enforced on all EC2 instances
- [ ] CloudTrail enabled and logging to S3
- [ ] VPC Flow Logs enabled
- [ ] Backup retention configured (30 days prod, 7 days dev)
- [ ] Deletion protection enabled (production only)
- [ ] SNS topic subscribed for alarm notifications
- [ ] IAM roles use least privilege policies
- [ ] MFA enabled for all IAM users
- [ ] GuardDuty enabled (recommended)
- [ ] AWS Config enabled for compliance (recommended)
- [ ] Secrets stored in Secrets Manager (not env vars)
- [ ] Container images scanned with Trivy
- [ ] Dependencies scanned for vulnerabilities
- [ ] HTTPS enforced on ALB (production)
- [ ] RDS SSL/TLS enforced
- [ ] No public subnet instances (except ALB)
- [ ] Auto Scaling configured with health checks

### Post-Deployment Checklist

- [ ] Smoke tests passed
- [ ] CloudWatch Dashboard populated with metrics
- [ ] Alarms triggering correctly (test with CloudWatch Synthetics)
- [ ] Logs flowing to CloudWatch
- [ ] Secrets Manager credentials accessible by application
- [ ] Database connectivity verified
- [ ] SSL certificate valid and not expiring soon
- [ ] Backup job completed successfully
- [ ] DNS records pointing to ALB (if applicable)
- [ ] Security groups verified (no unintended open ports)
- [ ] IAM roles attached to instances
- [ ] SSM Session Manager connectivity tested
- [ ] Auto Scaling tested (scale out and scale in)
- [ ] Documented in runbook and architecture docs

### Ongoing Security Operations

**Daily**:
- [ ] Review CloudWatch Alarms
- [ ] Check GuardDuty findings
- [ ] Monitor application error rates

**Weekly**:
- [ ] Review CloudTrail for anomalous activity
- [ ] Check for available security patches
- [ ] Review IAM access (unused roles, expired credentials)

**Monthly**:
- [ ] Update dependencies (Python packages)
- [ ] Review and update security group rules
- [ ] Test backup restoration procedure
- [ ] Review CloudWatch Insights for trends

**Quarterly**:
- [ ] Penetration testing (external if budget allows)
- [ ] Disaster recovery drill
- [ ] Security awareness training for team
- [ ] Review and update incident response plan
- [ ] Compliance audit (CIS benchmark)

**Annually**:
- [ ] Third-party penetration test
- [ ] SOC 2 audit (if applicable)
- [ ] Security architecture review
- [ ] Threat model update

## Additional Resources

### AWS Security Best Practices

- [AWS Well-Architected Framework - Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [AWS Security Best Practices Whitepaper](https://docs.aws.amazon.com/whitepapers/latest/aws-security-best-practices/welcome.html)
- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)

### Security Tools

- [AWS Security Hub](https://aws.amazon.com/security-hub/): Centralized security findings
- [AWS GuardDuty](https://aws.amazon.com/guardduty/): Threat detection
- [AWS Inspector](https://aws.amazon.com/inspector/): Vulnerability management
- [AWS Macie](https://aws.amazon.com/macie/): Sensitive data discovery
- [Prowler](https://github.com/prowler-cloud/prowler): AWS security assessment
- [ScoutSuite](https://github.com/nccgroup/ScoutSuite): Multi-cloud security auditing

### Compliance Frameworks

- [PCI-DSS on AWS](https://aws.amazon.com/compliance/pci-dss-level-1-faqs/)
- [HIPAA on AWS](https://aws.amazon.com/compliance/hipaa-compliance/)
- [SOC 2 on AWS](https://aws.amazon.com/compliance/soc-faqs/)
- [GDPR on AWS](https://aws.amazon.com/compliance/gdpr-center/)

---

**Document Version**: 1.0
**Last Updated**: 2024-01-15
**Review Frequency**: Quarterly
**Owner**: DevOps/Security Team
