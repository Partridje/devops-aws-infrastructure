# Secrets Access Control - Security Best Practices

## Overview

Command `make db-secret ENV=dev` is protected by **multiple layers of security**. This document explains each layer and provides recommendations for production environments.

## Current Security Layers

### Layer 1: AWS Account Authentication

**Requirement**: Valid AWS credentials

```bash
# Option 1: Access Key (not recommended for humans)
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCY

# Option 2: AWS SSO (recommended)
aws sso login --profile mycompany-dev

# Option 3: IAM Role (for EC2/ECS)
# Automatically provided via instance metadata
```

**Protection**:
- ✅ Without credentials → command fails immediately
- ✅ Credentials can be rotated/revoked centrally
- ✅ MFA can be enforced

**Error if no credentials**:
```bash
$ make db-secret ENV=dev
Unable to locate credentials. You can configure credentials by running "aws configure".
```

### Layer 2: IAM Permissions (Secrets Manager)

**Requirement**: `secretsmanager:GetSecretValue` permission

**Minimal IAM Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadDatabaseSecretsDevOnly",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": [
        "arn:aws:secretsmanager:eu-north-1:123456789:secret:demo-flask-app-dev-*",
        "arn:aws:secretsmanager:eu-north-1:123456789:secret:rds!*"
      ]
    }
  ]
}
```

**Protection**:
- ✅ Users only see secrets they're allowed to see
- ✅ Can restrict by environment (dev/prod)
- ✅ Can restrict by resource tags
- ✅ Can add time-based conditions

**Error if no permission**:
```bash
$ make db-secret ENV=prod

An error occurred (AccessDeniedException) when calling the GetSecretValue operation:
User: arn:aws:iam::123456789:user/developer is not authorized to perform:
secretsmanager:GetSecretValue on resource:
arn:aws:secretsmanager:eu-north-1:123456789:secret:demo-flask-app-prod-db-credentials-xxx
```

### Layer 3: KMS Permissions

**Requirement**: `kms:Decrypt` permission on the KMS key

**KMS Key Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Allow decrypt for specific roles",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::123456789:role/EC2-Application-Role",
          "arn:aws:iam::123456789:role/Developer-Role"
        ]
      },
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "secretsmanager.eu-north-1.amazonaws.com"
        }
      }
    }
  ]
}
```

**Protection**:
- ✅ Even with Secrets Manager access, can't decrypt without KMS permission
- ✅ Separate KMS keys for dev/prod
- ✅ KMS keys can require MFA for admin operations

**Error if no KMS permission**:
```bash
An error occurred (AccessDeniedException) when calling the GetSecretValue operation:
User is not authorized to perform: kms:Decrypt on the resource associated with this secret
```

### Layer 4: CloudTrail Audit Logging

**All secret access is logged**:

```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "IAMUser",
    "principalId": "AIDAI23HXS4EXAMPLE",
    "arn": "arn:aws:iam::123456789:user/developer",
    "accountId": "123456789",
    "userName": "developer"
  },
  "eventTime": "2024-01-15T10:30:00Z",
  "eventSource": "secretsmanager.amazonaws.com",
  "eventName": "GetSecretValue",
  "awsRegion": "eu-north-1",
  "sourceIPAddress": "203.0.113.42",
  "userAgent": "aws-cli/2.13.0",
  "requestParameters": {
    "secretId": "demo-flask-app-dev-db-connection-xxx"
  },
  "responseElements": null,
  "requestID": "abc-123-def-456",
  "eventID": "xyz-789-uvw-012",
  "readOnly": true,
  "eventType": "AwsApiCall",
  "recipientAccountId": "123456789"
}
```

**Monitoring**:
- ✅ Who accessed secrets
- ✅ When they accessed
- ✅ From which IP address
- ✅ Success or failure
- ✅ Can trigger alerts on unusual access

## Advanced Protection (Recommended for Production)

### 1. Environment-Based Access Control

**Developers**: Dev secrets only
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:*-dev-*"
    },
    {
      "Effect": "Deny",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:*-prod-*"
    }
  ]
}
```

**DevOps**: All environments, but requires MFA for prod
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DevWithoutMFA",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:*-dev-*"
    },
    {
      "Sid": "ProdRequiresMFA",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:*-prod-*",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        },
        "NumericLessThan": {
          "aws:MultiFactorAuthAge": "3600"
        }
      }
    }
  ]
}
```

### 2. IP-Based Restrictions

**Office network + VPN only**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "*",
      "Condition": {
        "IpAddress": {
          "aws:SourceIp": [
            "203.0.113.0/24",    // Office
            "10.0.0.0/8"         // VPN
          ]
        }
      }
    }
  ]
}
```

### 3. Time-Based Restrictions

**Business hours only**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:*-prod-*",
      "Condition": {
        "DateGreaterThan": {
          "aws:CurrentTime": "2024-01-01T09:00:00Z"
        },
        "DateLessThan": {
          "aws:CurrentTime": "2024-12-31T18:00:00Z"
        }
      }
    }
  ]
}
```

### 4. VPC Endpoint (Private Access Only)

**Add to VPC module**:
```hcl
# VPC Endpoint for Secrets Manager
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-secretsmanager-endpoint"
    }
  )
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name_prefix}-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-vpc-endpoints-sg"
    }
  )
}

# VPC Endpoint Policy (restrict to specific secrets)
resource "aws_vpc_endpoint_policy" "secretsmanager" {
  vpc_endpoint_id = aws_vpc_endpoint.secretsmanager.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "secretsmanager:GetSecretValue"
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.name_prefix}-*"
        ]
      }
    ]
  })
}
```

**Benefits**:
- ✅ Secrets only accessible from inside VPC
- ✅ No internet exposure
- ✅ Traffic stays on AWS backbone
- ✅ Additional Security Group protection

### 5. Session Tags (Attribute-Based Access Control)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalTag/Department": "Engineering",
          "aws:PrincipalTag/Environment": "dev"
        }
      }
    }
  ]
}
```

### 6. Resource Tags Enforcement

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "secretsmanager:ResourceTag/Team": "backend",
          "secretsmanager:ResourceTag/Sensitivity": "high"
        }
      }
    }
  ]
}
```

## Monitoring and Alerting

### CloudWatch Alarms for Suspicious Activity

```hcl
# Alert on failed secret access attempts
resource "aws_cloudwatch_log_metric_filter" "failed_secret_access" {
  name           = "failed-secret-access-${var.environment}"
  log_group_name = "/aws/cloudtrail/${var.environment}"

  pattern = '{($.eventName = "GetSecretValue") && ($.errorCode = "AccessDenied*")}'

  metric_transformation {
    name      = "FailedSecretAccess"
    namespace = "Security/SecretsManager"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "failed_secret_access" {
  alarm_name          = "high-failed-secret-access-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedSecretAccess"
  namespace           = "Security/SecretsManager"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alert on multiple failed secret access attempts"
  alarm_actions       = [var.sns_topic_arn]
}
```

### GuardDuty Integration

Enable GuardDuty to detect:
- Unusual API call patterns
- Access from unexpected locations
- Compromised credentials usage

## Example: Production IAM Policy

Complete example for production DevOps role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DevSecretsAnytime",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:*-dev-*"
    },
    {
      "Sid": "ProdSecretsWithMFAAndIP",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:*:secret:*-prod-*",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        },
        "NumericLessThan": {
          "aws:MultiFactorAuthAge": "3600"
        },
        "IpAddress": {
          "aws:SourceIp": [
            "203.0.113.0/24",
            "10.0.0.0/8"
          ]
        },
        "DateGreaterThan": {
          "aws:CurrentTime": "2024-01-01T00:00:00Z"
        },
        "DateLessThan": {
          "aws:CurrentTime": "2024-12-31T23:59:59Z"
        }
      }
    },
    {
      "Sid": "KMSDecryptForSecrets",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "arn:aws:kms:*:*:key/*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "secretsmanager.eu-north-1.amazonaws.com"
          ]
        }
      }
    }
  ]
}
```

## Testing Access Controls

### Test 1: Verify access works

```bash
$ aws sts get-caller-identity
{
    "UserId": "AIDAI23HXS4EXAMPLE",
    "Account": "123456789",
    "Arn": "arn:aws:iam::123456789:user/devops"
}

$ make db-secret ENV=dev
✅ SUCCESS
```

### Test 2: Verify MFA required for prod

```bash
# Without MFA session
$ make db-secret ENV=prod
❌ ACCESS DENIED

# Get MFA session
$ aws sts get-session-token \
  --serial-number arn:aws:iam::123456789:mfa/devops \
  --token-code 123456

# Use MFA session
$ export AWS_ACCESS_KEY_ID=ASIAIOSFODNN7EXAMPLE
$ export AWS_SECRET_ACCESS_KEY=...
$ export AWS_SESSION_TOKEN=...

$ make db-secret ENV=prod
✅ SUCCESS
```

### Test 3: Verify IP restrictions

```bash
# From home (not allowed)
$ curl ifconfig.me
198.51.100.42  # Not in allowed range

$ make db-secret ENV=prod
❌ ACCESS DENIED

# From office VPN
$ curl ifconfig.me
203.0.113.10  # In allowed range

$ make db-secret ENV=prod
✅ SUCCESS
```

## Incident Response

### Suspected credential compromise:

```bash
# 1. Revoke user credentials immediately
aws iam delete-access-key --user-name compromised-user --access-key-id AKIA...

# 2. Rotate database password
aws secretsmanager rotate-secret \
  --secret-id $(terraform output -raw master_user_secret_arn)

# 3. Review CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=compromised-user \
  --start-time "2024-01-01T00:00:00" \
  --max-results 50

# 4. Check for unauthorized secret access
aws logs filter-log-events \
  --log-group-name /aws/cloudtrail/production \
  --filter-pattern '{$.eventName = "GetSecretValue" && $.userIdentity.userName = "compromised-user"}'
```

## Summary

### Current Protection:
1. ✅ AWS account authentication required
2. ✅ IAM permissions for Secrets Manager
3. ✅ KMS decrypt permissions required
4. ✅ CloudTrail logging all access
5. ✅ S3 backend encryption

### Recommended Additional Protection:
1. 🔵 MFA required for production secrets
2. 🔵 IP-based restrictions (office/VPN only)
3. 🔵 VPC Endpoints (private access only)
4. 🔵 Time-based restrictions (business hours)
5. 🔵 CloudWatch alarms on failed attempts
6. 🔵 GuardDuty monitoring

### Risk Level:

| Scenario | Current Protection | With Recommendations |
|----------|-------------------|---------------------|
| Stolen laptop | ⚠️ Medium (if AWS keys cached) | ✅ Low (MFA + IP required) |
| Compromised IAM user | ⚠️ Medium (until detected) | ✅ Low (IP + MFA + monitoring) |
| Insider threat | ⚠️ Medium (CloudTrail logs) | ✅ Low (ABAC + monitoring) |
| External attacker | ✅ Low (needs AWS creds + IAM) | ✅ Very Low (multiple layers) |

## Next Steps

To implement advanced protection:

1. Review and apply production IAM policies
2. Enable MFA for all human users
3. Implement VPC endpoints for Secrets Manager
4. Set up CloudWatch alarms
5. Enable GuardDuty
6. Regular access reviews (monthly)
7. Periodic secret rotation (90 days)

---

**Remember**: Security is defense in depth. Each layer adds protection.
