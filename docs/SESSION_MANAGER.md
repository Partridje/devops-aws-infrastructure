# AWS Systems Manager Session Manager Guide

This guide explains how to securely access EC2 instances using AWS Systems Manager Session Manager instead of SSH.

## Overview

**Session Manager** provides secure, auditable shell access to EC2 instances **without**:
- ❌ SSH keys to manage
- ❌ Bastion hosts to maintain
- ❌ Open SSH ports (22) in security groups
- ❌ Public IP addresses on instances

**Instead, you get**:
- ✅ IAM-based access control
- ✅ Fully audited sessions (CloudTrail + CloudWatch Logs)
- ✅ No inbound ports required
- ✅ Port forwarding for secure tunneling
- ✅ Session recording for compliance

**Cost**: FREE (included with AWS Systems Manager)

---

## Prerequisites

### 1. AWS CLI with Session Manager Plugin

**Install AWS CLI** (if not already installed):
```bash
# macOS
brew install awscli

# Linux
pip install awscli

# Verify
aws --version
```

**Install Session Manager Plugin**:

**macOS**:
```bash
# Download and install
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin

# Verify
session-manager-plugin --version
```

**Linux**:
```bash
# Download
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"

# Install (RPM-based)
sudo yum install -y session-manager-plugin.rpm

# Or (Debian-based)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb

# Verify
session-manager-plugin --version
```

**Windows**:
1. Download installer from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
2. Run installer
3. Restart PowerShell/Command Prompt

### 2. IAM Permissions

Your IAM user/role needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession",
        "ssm:TerminateSession",
        "ssm:ResumeSession",
        "ssm:DescribeSessions",
        "ssm:GetConnectionStatus"
      ],
      "Resource": [
        "arn:aws:ec2:eu-north-1:*:instance/*",
        "arn:aws:ssm:eu-north-1::document/AWS-StartSSHSession"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "eu-north-1"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeInstanceInformation",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:ListCommands"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

**Quick setup** for administrators:
```bash
# Attach AWS managed policy (includes Session Manager permissions)
aws iam attach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

---

## Connecting to Instances

### List Available Instances

```bash
# List all instances managed by Session Manager
aws ssm describe-instance-information \
  --region eu-north-1 \
  --output table

# Filter by environment
aws ssm describe-instance-information \
  --region eu-north-1 \
  --filters "Key=tag:Environment,Values=prod" \
  --output table

# Get instance ID by name tag
INSTANCE_ID=$(aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Name,Values=demo-app-prod-*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"
```

### Start Interactive Session

```bash
# Start session
aws ssm start-session \
  --target $INSTANCE_ID \
  --region eu-north-1

# You're now connected!
# Prompt will show: sh-4.2$ or ssm-user@ip-xxx
```

**Example**:
```bash
$ aws ssm start-session --target i-1234567890abcdef0 --region eu-north-1

Starting session with SessionId: user@example.com-0abc1234def567890

sh-4.2$ whoami
ssm-user

sh-4.2$ sudo su -
[root@ip-10-0-1-23 ~]#

# Check application status
[root@ip-10-0-1-23 ~]# docker ps
[root@ip-10-0-1-23 ~]# docker logs $(docker ps -q)

# Exit session
[root@ip-10-0-1-23 ~]# exit
sh-4.2$ exit

Exiting session with sessionId: user@example.com-0abc1234def567890
```

### Execute Single Command

```bash
# Run command without interactive session
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker ps","df -h"]' \
  --region eu-north-1

# Get command output
COMMAND_ID=xxx  # From previous command output
aws ssm get-command-invocation \
  --command-id $COMMAND_ID \
  --instance-id $INSTANCE_ID \
  --region eu-north-1
```

---

## Common Tasks

### Check Application Logs

```bash
aws ssm start-session --target $INSTANCE_ID --region eu-north-1

# Once connected
sudo docker logs $(docker ps -q) --tail 100 --follow
```

### Restart Application

```bash
aws ssm start-session --target $INSTANCE_ID --region eu-north-1

# Once connected
sudo docker restart $(docker ps -q)

# Or via user data
sudo /var/lib/cloud/instance/scripts/part-001
```

### Check System Resources

```bash
aws ssm start-session --target $INSTANCE_ID --region eu-north-1

# CPU and memory
top

# Disk space
df -h

# Network connections
netstat -tulpn

# Docker stats
docker stats
```

### Access Database (via Port Forwarding)

Forward RDS port through Session Manager:

```bash
# Get RDS endpoint
RDS_ENDPOINT=$(terraform output -raw db_endpoint | cut -d':' -f1)

# Forward local port 5432 to RDS through EC2 instance
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${RDS_ENDPOINT}\"],\"portNumber\":[\"5432\"], \"localPortNumber\":[\"5432\"]}" \
  --region eu-north-1

# Now in another terminal, connect to localhost:5432
psql -h localhost -p 5432 -U app_user -d appdb
```

**Security note**: This creates temporary tunnel. RDS remains private, no direct internet access.

### Run Maintenance Scripts

```bash
# Copy script to instance
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "curl -o /tmp/maintenance.sh https://your-s3-bucket.s3.amazonaws.com/scripts/maintenance.sh",
    "chmod +x /tmp/maintenance.sh",
    "/tmp/maintenance.sh"
  ]' \
  --region eu-north-1
```

---

## Port Forwarding

### Forward Application Port (Local Testing)

```bash
# Forward remote port 5001 to local port 8080
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5001"],"localPortNumber":["8080"]}' \
  --region eu-north-1

# Access application at http://localhost:8080
curl http://localhost:8080/health
```

### SSH Tunnel (Advanced)

Use Session Manager as SSH ProxyCommand:

**~/.ssh/config**:
```
Host i-* mi-*
  ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p' --region eu-north-1"
  User ssm-user
```

**Usage**:
```bash
# Now SSH works through Session Manager
ssh i-1234567890abcdef0

# SCP files
scp myfile.txt i-1234567890abcdef0:/tmp/

# SFTP
sftp i-1234567890abcdef0
```

---

## Session Logging and Auditing

### CloudTrail Logging

All Session Manager actions are logged to CloudTrail:

```bash
# View session start events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StartSession \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --region eu-north-1

# View who started sessions
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StartSession \
  --region eu-north-1 \
  --query 'Events[*].[EventTime,Username]' \
  --output table
```

### CloudWatch Logs

Session commands can be logged to CloudWatch (if enabled):

**Enable session logging** (via Systems Manager Preferences):
```bash
aws ssm update-document \
  --name "SSM-SessionManagerRunShell" \
  --content '{
    "schemaVersion": "1.0",
    "description": "Document to hold regional settings for Session Manager",
    "sessionType": "Standard_Stream",
    "inputs": {
      "cloudWatchLogGroupName": "/aws/ssm/session-logs",
      "cloudWatchEncryptionEnabled": true,
      "s3BucketName": "",
      "s3EncryptionEnabled": false
    }
  }' \
  --region eu-north-1
```

**View session logs**:
```bash
aws logs tail /aws/ssm/session-logs --follow --region eu-north-1
```

### Session History

```bash
# List recent sessions
aws ssm describe-sessions \
  --state History \
  --region eu-north-1

# Get details of specific session
aws ssm describe-sessions \
  --filters "key=SessionId,value=user@example.com-0abc1234def567890" \
  --region eu-north-1
```

---

## Security Best Practices

### IAM Access Control

**Principle of Least Privilege**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSessionsOnProductionInstances",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession"
      ],
      "Resource": "arn:aws:ec2:eu-north-1:*:instance/*",
      "Condition": {
        "StringEquals": {
          "ssm:resourceTag/Environment": "prod"
        }
      }
    },
    {
      "Sid": "AllowSessionDocuments",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession"
      ],
      "Resource": [
        "arn:aws:ssm:eu-north-1::document/AWS-StartSSHSession",
        "arn:aws:ssm:eu-north-1::document/AWS-StartPortForwardingSession"
      ]
    }
  ]
}
```

**Read-only access** (view only, no execute):

```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:DescribeSessions",
    "ssm:GetConnectionStatus",
    "ssm:DescribeInstanceInformation"
  ],
  "Resource": "*"
}
```

### MFA Enforcement

Require MFA for Session Manager access:

```json
{
  "Effect": "Allow",
  "Action": "ssm:StartSession",
  "Resource": "*",
  "Condition": {
    "BoolIfExists": {
      "aws:MultiFactorAuthPresent": "true"
    }
  }
}
```

### Time-based Access

Limit sessions to business hours:

```json
{
  "Effect": "Allow",
  "Action": "ssm:StartSession",
  "Resource": "*",
  "Condition": {
    "DateGreaterThan": {
      "aws:CurrentTime": "2024-01-01T09:00:00Z"
    },
    "DateLessThan": {
      "aws:CurrentTime": "2024-12-31T18:00:00Z"
    }
  }
}
```

### Session Recording

Record all sessions for compliance:

1. **Enable S3 logging**:
   ```bash
   aws ssm create-document \
     --name SessionManagerPreferences \
     --document-type Session \
     --content '{
       "schemaVersion": "1.0",
       "description": "Session Manager Preferences",
       "sessionType": "Standard_Stream",
       "inputs": {
         "s3BucketName": "demo-app-session-logs",
         "s3EncryptionEnabled": true,
         "cloudWatchLogGroupName": "/aws/ssm/sessions",
         "cloudWatchEncryptionEnabled": true
       }
     }'
   ```

2. **Create S3 bucket for logs**:
   ```bash
   aws s3 mb s3://demo-app-session-logs --region eu-north-1
   aws s3api put-bucket-encryption \
     --bucket demo-app-session-logs \
     --server-side-encryption-configuration '{
       "Rules": [{
         "ApplyServerSideEncryptionByDefault": {
           "SSEAlgorithm": "AES256"
         }
       }]
     }'
   ```

---

## Troubleshooting

### Instance Not Showing in Session Manager

**Problem**: Instance doesn't appear in `describe-instance-information`

**Diagnosis**:
```bash
# Check instance status
aws ec2 describe-instance-status \
  --instance-ids $INSTANCE_ID \
  --region eu-north-1

# Check SSM Agent status
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region eu-north-1
```

**Common causes**:

1. **SSM Agent not running**
   - **Amazon Linux 2023**: Pre-installed, should be running
   - **Verify**: `sudo systemctl status amazon-ssm-agent`
   - **Start**: `sudo systemctl start amazon-ssm-agent`

2. **IAM instance profile missing permissions**
   - **Required**: `AmazonSSMManagedInstanceCore` policy
   - **Check**: EC2 instance IAM role has correct policy
   - **Fix**: Already configured in infrastructure (application_role)

3. **No internet connectivity**
   - **Required**: Instance must reach Systems Manager endpoints
   - **Check**: NAT Gateway working, route tables correct
   - **Verify**: `curl https://ssm.eu-north-1.amazonaws.com`

4. **Security group blocking outbound**
   - **Required**: HTTPS outbound (443) to AWS services
   - **Check**: Security group allows outbound to 0.0.0.0/0:443
   - **Fix**: Already configured in infrastructure

### Session Fails to Start

**Problem**: `TargetNotConnected` or session times out

**Solutions**:

1. **Wait 5 minutes** after instance launch (SSM Agent registration)

2. **Restart SSM Agent**:
   ```bash
   aws ssm send-command \
     --instance-ids $INSTANCE_ID \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["sudo systemctl restart amazon-ssm-agent"]' \
     --region eu-north-1
   ```

3. **Check CloudWatch Logs** for SSM Agent errors:
   ```bash
   aws logs tail /aws/ssm/instance-logs --follow
   ```

### Permission Denied

**Problem**: `AccessDeniedException` when starting session

**Solutions**:

1. **Verify IAM permissions**:
   ```bash
   aws iam simulate-principal-policy \
     --policy-source-arn arn:aws:iam::ACCOUNT:user/USERNAME \
     --action-names ssm:StartSession \
     --resource-arns "arn:aws:ec2:eu-north-1:ACCOUNT:instance/$INSTANCE_ID"
   ```

2. **Check instance resource tags** (if using tag-based conditions)

3. **Verify AWS CLI configuration**:
   ```bash
   aws sts get-caller-identity
   ```

---

## Comparison: Session Manager vs SSH

| Feature | Session Manager | SSH |
|---------|----------------|-----|
| **Setup** | No keys, automatic | Manage SSH keys |
| **Access Control** | IAM policies | SSH authorized_keys |
| **Auditing** | CloudTrail + CloudWatch | Custom logging |
| **Security Groups** | No inbound rules needed | Requires port 22 open |
| **Bastion Host** | Not needed | Required for private instances |
| **MFA** | Native IAM MFA | Third-party solutions |
| **Port Forwarding** | Yes | Yes |
| **File Transfer** | Via port forward or S3 | Native (SCP/SFTP) |
| **Cost** | FREE | Bastion host costs |
| **Compliance** | Session recording | Manual setup |

**Recommendation**: Use Session Manager for all production access. SSH can be disabled entirely.

---

## Advanced Use Cases

### Automated Health Checks

```bash
#!/bin/bash
# health-check.sh - Run automated checks on all instances

INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text \
  --region eu-north-1)

for instance in $INSTANCES; do
  echo "Checking $instance..."

  aws ssm send-command \
    --instance-ids $instance \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=[
      "echo Instance: $(hostname)",
      "echo Uptime: $(uptime)",
      "echo Disk: $(df -h / | tail -1 | awk \"{print $5}\")",
      "echo Memory: $(free -m | grep Mem | awk \"{print $3/$2 * 100.0}\")",
      "echo Docker: $(docker ps --format \"{{.Names}}: {{.Status}}\")"
    ]' \
    --output text \
    --region eu-north-1
done
```

### Emergency Commands Across Fleet

```bash
# Restart all application containers
aws ssm send-command \
  --targets "Key=tag:Environment,Values=prod" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker restart $(docker ps -q)"]' \
  --region eu-north-1

# Clear cache on all instances
aws ssm send-command \
  --targets "Key=tag:Environment,Values=prod" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["rm -rf /tmp/cache/*"]' \
  --region eu-north-1
```

### Collect Logs from All Instances

```bash
# Collect and upload logs to S3
aws ssm send-command \
  --targets "Key=tag:Environment,Values=prod" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "docker logs $(docker ps -q) > /tmp/app.log 2>&1",
    "aws s3 cp /tmp/app.log s3://demo-app-logs/$(hostname)/$(date +%Y%m%d-%H%M%S).log"
  ]' \
  --region eu-north-1
```

---

## Summary

**Session Manager is configured and ready to use** with your infrastructure:

✅ **Setup**:
- SSM Agent pre-installed (Amazon Linux 2023)
- IAM role with required permissions
- Security groups allow SSM endpoints
- No SSH keys or bastion hosts needed

✅ **Access**:
```bash
# 1. List instances
aws ssm describe-instance-information --region eu-north-1

# 2. Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text --region eu-north-1)

# 3. Connect
aws ssm start-session --target $INSTANCE_ID --region eu-north-1
```

✅ **Security**:
- IAM-based access control
- CloudTrail audit logging
- No SSH ports exposed
- Optional session recording

**Cost**: FREE - No additional charges

---

**Related Documentation**:
- [Secrets Rotation Guide](./SECRETS_ROTATION.md)
- [WAF Setup Guide](./WAF_SETUP.md)
- [Main README](../README.md)

**AWS Documentation**:
- [Session Manager Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- [IAM Policies for Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-create-iam-instance-profile.html)
