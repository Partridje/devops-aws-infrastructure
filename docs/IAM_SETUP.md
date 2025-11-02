# IAM Setup Guide

## Overview

This guide provides step-by-step instructions for setting up IAM permissions to deploy this infrastructure.

## Quick Comparison

| Approach | Time | Best For | Pros | Cons |
|----------|------|----------|------|------|
| **Group + User (Option A)** | 7 min | Teams, scalable setup | ✅ AWS best practice<br>✅ Easy to add users<br>✅ Centralized permissions | ⏱️ Slightly longer setup |
| **Direct User (Option B)** | 5 min | Single user, quick test | ✅ Fastest<br>✅ Simple | ❌ Not scalable<br>❌ Hard to manage multiple users |
| **Production (Custom Policy)** | 15 min | Production, strict security | ✅ Least privilege<br>✅ Compliance-ready<br>✅ Auditable | ⏱️ More complex<br>📝 Requires policy maintenance |

**💡 Recommendation**: Start with **Option A (Group + User)** - only 2 minutes more than Option B, but follows AWS best practices and makes future expansion easier.

---

## Quick Start (Recommended for Testing)

### Option A: Create Group + User (BEST PRACTICE - 7 minutes)

**Best for**: Testing with proper structure, easy to add more users later

#### Step 1: Create IAM Group

1. **Open IAM Console**: https://console.aws.amazon.com/iam/
2. **User groups** → **Create group**
3. **Group name**: `TerraformAdmins`
4. **Attach permissions policies**:
   - Search and select: ✅ **AdministratorAccess**
5. **Create group**

#### Step 2: Create User and Add to Group

1. **Users** → **Create user**
2. **User name**: `terraform-admin` (or your name, e.g., `john-terraform`)
3. ✅ **Provide user access to the AWS Management Console** (optional, for console access)
4. **Next**
5. **Set Permissions**:
   - Select **Add user to group**
   - ✅ Select **TerraformAdmins** group
6. **Next** → **Create user**

#### Step 3: Create Access Key

1. Go to user details page (`terraform-admin`)
2. **Security credentials** tab
3. **Create access key**
4. Use case: **Command Line Interface (CLI)**
5. ✅ Check confirmation
6. **Create access key**
7. **⚠️ IMPORTANT**: Download `.csv` file or copy keys NOW (you won't see them again!)

**Benefits:**
- ✅ Easy to add more users to `TerraformAdmins` group
- ✅ Change permissions once → applies to all users
- ✅ Follows AWS best practices

---

### Option B: Create User Only (Quick - 5 minutes)

**Best for**: Single user, quick testing

1. **Open IAM Console**: https://console.aws.amazon.com/iam/
2. **Create User**:
   - Click **Users** → **Create user**
   - User name: `terraform-admin`
   - ✅ **Provide user access to the AWS Management Console** (optional, for console access)
   - ✅ **I want to create an IAM user**
3. **Set Permissions**:
   - Select **Attach policies directly**
   - Search and select: ✅ **AdministratorAccess**
4. **Review and Create**
5. **Create Access Key**:
   - Go to user details page
   - **Security credentials** tab
   - **Create access key**
   - Use case: **Command Line Interface (CLI)**
   - **⚠️ IMPORTANT**: Download `.csv` file or copy keys NOW (you won't see them again!)

**Note**: For production or team environments, use Option A (Group-based)

### Configure AWS CLI

```bash
# Configure with your new credentials
aws configure

# Enter when prompted:
# AWS Access Key ID: <paste your Access Key ID>
# AWS Secret Access Key: <paste your Secret Access Key>
# Default region name: eu-north-1
# Default output format: json

# Verify it works
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/terraform-admin"
# }
```

**✅ You're ready to deploy!** Continue with [QUICK_START.md](../QUICK_START.md)

---

## Production Setup (Least Privilege)

### Custom Policy for Terraform

**Best for**: Production environments, strict security requirements

#### Step 1: Create Custom Policy

1. **Open IAM Console** → **Policies** → **Create policy**
2. **Switch to JSON tab**
3. **Paste this policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformVPCAndNetworking",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:DescribeVpcs",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:DescribeSubnets",
        "ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:DescribeInternetGateways",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway",
        "ec2:DescribeNatGateways",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:DescribeAddresses",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeAccountAttributes"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformSecurityGroups",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSecurityGroupRules",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:ModifySecurityGroupRules"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformEC2",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeImages",
        "ec2:DescribeVolumes",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:ModifyVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:DescribeInstanceAttribute",
        "ec2:ModifyInstanceAttribute",
        "ec2:DescribeInstanceCreditSpecifications"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformAutoScaling",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:CreateLaunchConfiguration",
        "autoscaling:DeleteLaunchConfiguration",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DescribeTags",
        "autoscaling:PutScalingPolicy",
        "autoscaling:DeletePolicy",
        "autoscaling:DescribePolicies",
        "autoscaling:PutLifecycleHook",
        "autoscaling:DeleteLifecycleHook",
        "autoscaling:DescribeLifecycleHooks",
        "ec2:CreateLaunchTemplate",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:ModifyLaunchTemplate",
        "ec2:CreateLaunchTemplateVersion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformLoadBalancers",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags",
        "elasticloadbalancing:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformRDS",
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBInstance",
        "rds:DeleteDBInstance",
        "rds:DescribeDBInstances",
        "rds:ModifyDBInstance",
        "rds:CreateDBSubnetGroup",
        "rds:DeleteDBSubnetGroup",
        "rds:DescribeDBSubnetGroups",
        "rds:CreateDBParameterGroup",
        "rds:DeleteDBParameterGroup",
        "rds:DescribeDBParameterGroups",
        "rds:ModifyDBParameterGroup",
        "rds:AddTagsToResource",
        "rds:RemoveTagsFromResource",
        "rds:ListTagsForResource",
        "rds:CreateDBSnapshot",
        "rds:DeleteDBSnapshot",
        "rds:DescribeDBSnapshots"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformSecretsManager",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret",
        "secretsmanager:DeleteSecret",
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecret",
        "secretsmanager:TagResource",
        "secretsmanager:UntagResource",
        "secretsmanager:ListSecrets",
        "secretsmanager:RotateSecret",
        "secretsmanager:CancelRotateSecret"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformKMS",
      "Effect": "Allow",
      "Action": [
        "kms:CreateKey",
        "kms:CreateAlias",
        "kms:DeleteAlias",
        "kms:DescribeKey",
        "kms:ListKeys",
        "kms:ListAliases",
        "kms:EnableKeyRotation",
        "kms:DisableKeyRotation",
        "kms:GetKeyRotationStatus",
        "kms:GetKeyPolicy",
        "kms:PutKeyPolicy",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ListResourceTags",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformIAM",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:UpdateRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:ListInstanceProfiles",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:PassRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformCloudWatch",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:DeleteRetentionPolicy",
        "logs:TagLogGroup",
        "logs:UntagLogGroup",
        "logs:ListTagsLogGroup",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:PutDashboard",
        "cloudwatch:DeleteDashboards",
        "cloudwatch:GetDashboard",
        "cloudwatch:ListDashboards",
        "cloudwatch:TagResource",
        "cloudwatch:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformSNS",
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic",
        "sns:DeleteTopic",
        "sns:GetTopicAttributes",
        "sns:SetTopicAttributes",
        "sns:Subscribe",
        "sns:Unsubscribe",
        "sns:ListSubscriptionsByTopic",
        "sns:ListTopics",
        "sns:TagResource",
        "sns:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformS3State",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketEncryption",
        "s3:PutBucketEncryption",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging"
      ],
      "Resource": [
        "arn:aws:s3:::terraform-state-*",
        "arn:aws:s3:::terraform-state-*/*"
      ]
    },
    {
      "Sid": "TerraformDynamoDBLock",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:TagResource",
        "dynamodb:UntagResource",
        "dynamodb:ListTagsOfResource"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock-*"
    },
    {
      "Sid": "TerraformSSM",
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:DeleteParameter",
        "ssm:DescribeParameters",
        "ssm:AddTagsToResource",
        "ssm:RemoveTagsFromResource",
        "ssm:ListTagsForResource"
      ],
      "Resource": "*"
    }
  ]
}
```

4. **Next: Tags** (optional)
5. **Next: Review**
   - Name: `TerraformDeployPolicy`
   - Description: `Minimum permissions for deploying demo-flask-app infrastructure`
6. **Create policy**

#### Step 2: Create IAM Group with Custom Policy

1. **User groups** → **Create group**
2. **Group name**: `TerraformDeploy`
3. **Attach permissions policies**:
   - Search and select: ✅ **TerraformDeployPolicy** (your custom policy)
4. **Create group**

#### Step 3: Create User and Add to Group

1. **Users** → **Create user**
2. User name: `terraform-deploy` (or your name)
3. **Next**
4. **Set Permissions**:
   - Select **Add user to group**
   - ✅ Select **TerraformDeploy** group
5. **Next** → **Create user**
6. **Create access key** (same steps as Quick Start above)

**Benefits:**
- ✅ Easy to add developers, reviewers, or CI/CD users to the same group
- ✅ Separate groups for different environments (dev, staging, prod)
- ✅ Audit group membership instead of individual policies

---

## Advanced: Multi-Environment Group Architecture

**Best for**: Teams with multiple environments (dev, staging, prod)

### Recommended Group Structure

```
TerraformAdmins (AdministratorAccess)
├── john-admin
└── jane-admin

TerraformDev (TerraformDeployPolicy + dev-only resources)
├── developer1
├── developer2
└── ci-cd-dev

TerraformStaging (TerraformDeployPolicy + staging-only)
├── developer1
└── ci-cd-staging

TerraformProd (TerraformDeployPolicy + prod-only + MFA required)
├── john-admin (also in TerraformAdmins)
└── ci-cd-prod

TerraformReadOnly (Read-only access for all environments)
├── analyst1
├── auditor1
└── support-team
```

### Example: Read-Only Group

Create a group for users who only need to view infrastructure:

1. **Create policy** `TerraformReadOnlyPolicy`:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "rds:Describe*",
        "elasticloadbalancing:Describe*",
        "autoscaling:Describe*",
        "cloudwatch:Describe*",
        "cloudwatch:Get*",
        "cloudwatch:List*",
        "logs:Describe*",
        "logs:Get*",
        "s3:ListBucket",
        "s3:GetObject",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets"
      ],
      "Resource": "*"
    }
  ]
}
```

2. **Create group** `TerraformReadOnly` with this policy
3. **Add users** who need read-only access

---

## Root User vs AdministratorAccess

### Key Differences

| Capability | Root User | IAM User (AdministratorAccess) |
|------------|-----------|--------------------------------|
| **Access Level** | Unrestricted account owner | Full AWS service access |
| **Can be restricted?** | ❌ No | ✅ Yes (via policies) |
| **Can be deleted?** | ❌ No | ✅ Yes |
| **Billing access** | ✅ Always | ⚠️ Only if enabled |
| **Close AWS account** | ✅ Yes | ❌ No |
| **Change account email** | ✅ Yes | ❌ No |
| **CloudTrail audit** | "Root" (anonymous) | Specific username |
| **Recovery if compromised** | ❌ Very difficult | ✅ Root can delete IAM user |

### When to Use Root User

**ONLY for these tasks (do NOT use daily):**
1. ✅ Initial AWS account setup
2. ✅ Enable MFA on root account
3. ✅ Create first IAM admin user
4. ✅ Change account email or payment method
5. ✅ Close AWS account
6. ✅ Restore access if all IAM admins locked out
7. ✅ View/change AWS Support plan
8. ✅ Register for Reserved Instance Marketplace (seller)

**After initial setup: Lock root credentials away! Use IAM users for everything else.**

### Why IAM Users Are Safer

```
Compromised Root User:
├── Attacker can delete all IAM users
├── Attacker can change account email
├── Attacker can remove MFA
└── ⚠️ YOU MAY LOSE ACCOUNT PERMANENTLY

Compromised IAM User (even with AdministratorAccess):
├── Root can see activity in CloudTrail
├── Root can delete compromised IAM user
├── Root can revoke access keys
└── ✅ Account recovered in minutes
```

### AWS Recommendation

> "We strongly recommend that you do not use the root user for your everyday tasks, even the administrative ones. Instead, adhere to the best practice of using the root user only to create your first IAM user."
>
> — AWS Security Best Practices

### What You Should Do RIGHT NOW

Since you're currently logged in as root:

#### Step 1: Secure Root Account (5 minutes)

```
1. Enable MFA on Root:
   → AWS Console (top-right) → Security credentials
   → Multi-factor authentication (MFA) → Activate MFA
   → Use Authenticator app (Google Authenticator, Authy)

2. Delete Root Access Keys (if any exist):
   → Security credentials → Access keys
   → If you see any keys: DELETE them
   → Root should NEVER have API access keys

3. Create IAM admin user (follow this guide)

4. Test IAM admin user access

5. Log out from root

6. Store root password in password manager (1Password, LastPass)
```

#### Step 2: Daily Work

```
✅ DO: Use IAM user (terraform-admin) for everything
   - aws configure (with IAM user keys)
   - terraform apply
   - AWS Console login

❌ DON'T: Use root for daily operations
   - Only login as root for account-level changes
   - Maybe once every 6-12 months
```

#### Step 3: Enable Billing Access for IAM Users

If you want your IAM admin to see billing:

1. **Still logged in as root**: https://console.aws.amazon.com/billing/home#/account
2. Scroll to **IAM User and Role Access to Billing Information**
3. Click **Edit**
4. ✅ Check **Activate IAM Access**
5. **Update**

Now your `terraform-admin` IAM user can access Cost Explorer and billing.

---

## Security Best Practices

### 1. Use MFA (Multi-Factor Authentication)

Enable MFA for your IAM user:

1. **IAM Console** → **Users** → Select your user
2. **Security credentials** tab
3. **Assign MFA device**
4. Follow the setup wizard

### 2. Rotate Access Keys Regularly

```bash
# Create new access key (you can have 2 active keys)
aws iam create-access-key --user-name terraform-admin

# Update aws configure with new key
aws configure

# Delete old key after testing
aws iam delete-access-key --access-key-id OLD_KEY_ID --user-name terraform-admin
```

### 3. Use AWS Vault (Optional but Recommended)

Store credentials securely in your system keychain:

```bash
# Install aws-vault (macOS)
brew install aws-vault

# Add credentials
aws-vault add terraform-admin

# Use with terraform
aws-vault exec terraform-admin -- terraform plan
```

### 4. Never Commit Credentials to Git

Add to `.gitignore` (already included):
```
# AWS credentials
.aws/
*.pem
*.key
credentials
```

---

## Troubleshooting

### Error: "Access Denied" or "UnauthorizedOperation"

**Solution**: Check your IAM policy includes the required permission.

Example error:
```
Error: error creating EC2 Instance: UnauthorizedOperation:
You are not authorized to perform this operation.
```

**Fix**: Ensure your policy includes `ec2:RunInstances`.

### Error: "User is not authorized to perform: sts:GetCallerIdentity"

**Solution**: Your AWS CLI is not configured correctly.

```bash
# Reconfigure
aws configure

# Verify
aws sts get-caller-identity
```

### Error: "The security token included in the request is expired"

**Solution**: Your temporary credentials expired (if using MFA or aws-vault).

```bash
# Re-authenticate
aws-vault exec terraform-admin -- aws sts get-caller-identity
```

---

## Verification Checklist

After setup, verify everything works:

```bash
# 1. Identity check
aws sts get-caller-identity
# ✅ Should return your user ARN

# 2. S3 access (for Terraform state)
aws s3 ls
# ✅ Should list buckets (or empty if none exist)

# 3. EC2 describe (read-only test)
aws ec2 describe-vpcs
# ✅ Should return VPC list (or empty)

# 4. IAM read access
aws iam get-user
# ✅ Should return your user details
```

If all commands succeed, you're ready to deploy! 🚀

---

## Appendix: CLI Alternative (for automation)

### Create Group + User via AWS CLI

```bash
# 1. Create group
aws iam create-group --group-name TerraformAdmins

# 2. Attach policy to group
aws iam attach-group-policy \
  --group-name TerraformAdmins \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# 3. Create user
aws iam create-user --user-name terraform-admin

# 4. Add user to group
aws iam add-user-to-group \
  --user-name terraform-admin \
  --group-name TerraformAdmins

# 5. Create access key
aws iam create-access-key --user-name terraform-admin

# Output will show AccessKeyId and SecretAccessKey - save them!

# 6. Configure AWS CLI
aws configure
# Enter the AccessKeyId and SecretAccessKey from step 5
```

### List Groups and Members

```bash
# List all groups
aws iam list-groups

# List users in a group
aws iam get-group --group-name TerraformAdmins

# List groups for a user
aws iam list-groups-for-user --user-name terraform-admin

# List policies attached to group
aws iam list-attached-group-policies --group-name TerraformAdmins
```

---

## What's Next?

Continue with:
- **[QUICK_START.md](../QUICK_START.md)** - 15-minute deployment
- **[DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md)** - Comprehensive guide

---

## Additional Resources

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Terraform AWS Provider Authentication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration)
- [AWS CLI Configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html)
