#!/bin/bash

# Setup Terraform Remote Backend (S3 + DynamoDB)
# This script creates the necessary AWS resources for Terraform remote state

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration file to store backend settings
CONFIG_FILE=".terraform-backend-config"
PROJECT_NAME="demo-flask-app"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check AWS credentials
echo -e "${GREEN}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}AWS credentials are not configured. Run 'aws configure' first.${NC}"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account: ${AWS_ACCOUNT_ID}${NC}"

# Check if configuration file exists
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Found existing backend configuration!${NC}"
    source "$CONFIG_FILE"
    echo -e "${YELLOW}Using saved configuration:${NC}"
    echo -e "${YELLOW}  Region: ${AWS_REGION}${NC}"
    echo -e "${YELLOW}  Bucket: ${BUCKET_NAME}${NC}"
    echo -e "${YELLOW}  DynamoDB Table: ${DYNAMODB_TABLE}${NC}"
    echo ""
    read -p "Continue with this configuration? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Exiting. Delete $CONFIG_FILE to create new backend.${NC}"
        exit 0
    fi
else
    # First time setup - use parameters or defaults
    AWS_REGION="${1:-eu-north-1}"
    BUCKET_NAME="${2:-terraform-state-${PROJECT_NAME}-${AWS_ACCOUNT_ID}}"
    DYNAMODB_TABLE="terraform-state-lock-${PROJECT_NAME}"

    echo -e "${GREEN}Setting up NEW Terraform backend...${NC}"
    echo -e "${YELLOW}Region: ${AWS_REGION}${NC}"
    echo -e "${YELLOW}Bucket: ${BUCKET_NAME}${NC}"
    echo -e "${YELLOW}DynamoDB Table: ${DYNAMODB_TABLE}${NC}"
    echo ""
fi

# Create S3 bucket
echo -e "${GREEN}Creating S3 bucket for Terraform state...${NC}"
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo -e "${YELLOW}✓ Bucket ${BUCKET_NAME} already exists${NC}"
else
    # Note: us-east-1 is the only region that does NOT require LocationConstraint
    if [ "${AWS_REGION}" == "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${AWS_REGION}"
    else
        # All other regions (including eu-north-1) require LocationConstraint
        aws s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${AWS_REGION}" \
            --create-bucket-configuration LocationConstraint="${AWS_REGION}"
    fi
    echo -e "${GREEN}✓ Bucket ${BUCKET_NAME} created${NC}"
fi

# Enable versioning
echo -e "${GREEN}Enabling versioning on S3 bucket...${NC}"
aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled
echo -e "${GREEN}✓ Versioning enabled${NC}"

# Enable encryption
echo -e "${GREEN}Enabling encryption on S3 bucket...${NC}"
aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": true
        }]
    }'
echo -e "${GREEN}✓ Encryption enabled${NC}"

# Block public access
echo -e "${GREEN}Blocking public access to S3 bucket...${NC}"
aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo -e "${GREEN}✓ Public access blocked${NC}"

# Add bucket policy
echo -e "${GREEN}Adding bucket policy...${NC}"
cat > /tmp/bucket-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EnforcedTLS",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF

aws s3api put-bucket-policy \
    --bucket "${BUCKET_NAME}" \
    --policy file:///tmp/bucket-policy.json

rm /tmp/bucket-policy.json
echo -e "${GREEN}✓ Bucket policy applied${NC}"

# Enable bucket logging (optional)
echo -e "${GREEN}Configuring bucket logging...${NC}"
LOGGING_BUCKET="${BUCKET_NAME}-logs"

if aws s3api head-bucket --bucket "${LOGGING_BUCKET}" 2>/dev/null; then
    echo -e "${YELLOW}✓ Logging bucket ${LOGGING_BUCKET} already exists${NC}"
else
    # Note: us-east-1 is the only region that does NOT require LocationConstraint
    if [ "${AWS_REGION}" == "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "${LOGGING_BUCKET}" \
            --region "${AWS_REGION}" 2>/dev/null || true
    else
        # All other regions (including eu-north-1) require LocationConstraint
        aws s3api create-bucket \
            --bucket "${LOGGING_BUCKET}" \
            --region "${AWS_REGION}" \
            --create-bucket-configuration LocationConstraint="${AWS_REGION}" 2>/dev/null || true
    fi
fi

# Create DynamoDB table for state locking
echo -e "${GREEN}Creating DynamoDB table for state locking...${NC}"
if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" &> /dev/null; then
    echo -e "${YELLOW}✓ DynamoDB table ${DYNAMODB_TABLE} already exists${NC}"
else
    aws dynamodb create-table \
        --table-name "${DYNAMODB_TABLE}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${AWS_REGION}" \
        --tags Key=Name,Value="${DYNAMODB_TABLE}" Key=ManagedBy,Value=Terraform

    echo -e "${GREEN}Waiting for table to be active...${NC}"
    aws dynamodb wait table-exists \
        --table-name "${DYNAMODB_TABLE}" \
        --region "${AWS_REGION}"

    echo -e "${GREEN}✓ DynamoDB table ${DYNAMODB_TABLE} created${NC}"
fi

# Enable Point-in-Time Recovery for DynamoDB
echo -e "${GREEN}Enabling Point-in-Time Recovery for DynamoDB...${NC}"
aws dynamodb update-continuous-backups \
    --table-name "${DYNAMODB_TABLE}" \
    --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
    --region "${AWS_REGION}" &> /dev/null || echo -e "${YELLOW}Note: Point-in-time recovery may already be enabled${NC}"

echo -e "${GREEN}✓ Point-in-Time Recovery enabled${NC}"

# Save configuration for future runs
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}Saving backend configuration...${NC}"
    cat > "$CONFIG_FILE" <<EOF
# Terraform Backend Configuration
# Created: $(date)
# This file is used by setup-terraform-backend.sh to remember backend settings

AWS_REGION="${AWS_REGION}"
BUCKET_NAME="${BUCKET_NAME}"
DYNAMODB_TABLE="${DYNAMODB_TABLE}"
EOF
    echo -e "${GREEN}✓ Configuration saved to ${CONFIG_FILE}${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Terraform Backend Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Add the following to your Terraform backend configuration:"
echo ""
echo -e "${YELLOW}terraform {${NC}"
echo -e "${YELLOW}  backend \"s3\" {${NC}"
echo -e "${YELLOW}    bucket         = \"${BUCKET_NAME}\"${NC}"
echo -e "${YELLOW}    key            = \"<environment>/terraform.tfstate\"${NC}"
echo -e "${YELLOW}    region         = \"${AWS_REGION}\"${NC}"
echo -e "${YELLOW}    encrypt        = true${NC}"
echo -e "${YELLOW}    dynamodb_table = \"${DYNAMODB_TABLE}\"${NC}"
echo -e "${YELLOW}  }${NC}"
echo -e "${YELLOW}}${NC}"
echo ""
echo -e "Resources created:"
echo -e "  • S3 Bucket: ${GREEN}${BUCKET_NAME}${NC}"
echo -e "  • DynamoDB Table: ${GREEN}${DYNAMODB_TABLE}${NC}"
echo -e "  • Region: ${GREEN}${AWS_REGION}${NC}"
echo ""
echo -e "${GREEN}Configuration saved to: ${CONFIG_FILE}${NC}"
echo -e "${YELLOW}Next time you run this script, it will use the saved configuration.${NC}"
echo -e "${YELLOW}To create a new backend, delete ${CONFIG_FILE} first.${NC}"
