#!/bin/bash

#####################################
# Cleanup Terraform Backend
#####################################
# This script removes S3 buckets and DynamoDB table
# used for Terraform state management.
#
# ⚠️  WARNING: This will delete ALL terraform state!
# Only run this when completely removing the project.
#
# Usage:
#   ./scripts/cleanup-terraform-backend.sh
#####################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="${PROJECT_NAME:-demo-flask-app}"
AWS_REGION="${AWS_REGION:-eu-north-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

STATE_BUCKET="terraform-state-${PROJECT_NAME}-eu-${AWS_ACCOUNT_ID}"
LOGS_BUCKET="terraform-state-${PROJECT_NAME}-eu-${AWS_ACCOUNT_ID}-logs"
LOCK_TABLE="terraform-state-lock-${PROJECT_NAME}"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Terraform Backend Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "This will DELETE:"
echo "  - S3 Bucket: ${STATE_BUCKET}"
echo "  - S3 Bucket: ${LOGS_BUCKET}"
echo "  - DynamoDB Table: ${LOCK_TABLE}"
echo ""
echo -e "${RED}⚠️  WARNING: All Terraform state will be lost!${NC}"
echo -e "${RED}⚠️  Make sure all infrastructure is destroyed first!${NC}"
echo ""

# Ask for confirmation
read -p "Type 'DELETE' to confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Starting cleanup...${NC}"
echo ""

#####################################
# 1. Delete State S3 Bucket
#####################################
echo "1. Checking S3 state bucket: ${STATE_BUCKET}"

if aws s3 ls "s3://${STATE_BUCKET}" --region "${AWS_REGION}" 2>/dev/null; then
    echo "   Found bucket, checking contents..."

    # Check if bucket has objects
    OBJECT_COUNT=$(aws s3 ls "s3://${STATE_BUCKET}" --recursive --region "${AWS_REGION}" | wc -l)

    if [ "$OBJECT_COUNT" -gt 0 ]; then
        echo "   Bucket contains ${OBJECT_COUNT} objects"
        echo "   Removing all objects..."
        aws s3 rm "s3://${STATE_BUCKET}" --recursive --region "${AWS_REGION}"
    else
        echo "   Bucket is empty"
    fi

    # Delete all versions (for versioned buckets)
    echo "   Removing all versions..."
    aws s3api list-object-versions \
        --bucket "${STATE_BUCKET}" \
        --region "${AWS_REGION}" \
        --output json \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' | \
    jq -r '.Objects[]? | "--key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
    xargs -I {} aws s3api delete-object --bucket "${STATE_BUCKET}" --region "${AWS_REGION}" {} 2>/dev/null || true

    # Delete delete markers
    aws s3api list-object-versions \
        --bucket "${STATE_BUCKET}" \
        --region "${AWS_REGION}" \
        --output json \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' | \
    jq -r '.Objects[]? | "--key \"\(.Key)\" --version-id \"\(.VersionId)\""' | \
    xargs -I {} aws s3api delete-object --bucket "${STATE_BUCKET}" --region "${AWS_REGION}" {} 2>/dev/null || true

    echo "   Deleting bucket..."
    aws s3 rb "s3://${STATE_BUCKET}" --region "${AWS_REGION}" --force
    echo -e "   ${GREEN}✓ State bucket deleted${NC}"
else
    echo -e "   ${YELLOW}Bucket not found (already deleted?)${NC}"
fi

echo ""

#####################################
# 2. Delete Logs S3 Bucket
#####################################
echo "2. Checking S3 logs bucket: ${LOGS_BUCKET}"

if aws s3 ls "s3://${LOGS_BUCKET}" --region "${AWS_REGION}" 2>/dev/null; then
    echo "   Found bucket, removing contents..."
    aws s3 rm "s3://${LOGS_BUCKET}" --recursive --region "${AWS_REGION}" 2>/dev/null || true

    echo "   Deleting bucket..."
    aws s3 rb "s3://${LOGS_BUCKET}" --region "${AWS_REGION}" --force
    echo -e "   ${GREEN}✓ Logs bucket deleted${NC}"
else
    echo -e "   ${YELLOW}Bucket not found (already deleted?)${NC}"
fi

echo ""

#####################################
# 3. Delete DynamoDB Lock Table
#####################################
echo "3. Checking DynamoDB table: ${LOCK_TABLE}"

if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo "   Found table, deleting..."
    aws dynamodb delete-table --table-name "${LOCK_TABLE}" --region "${AWS_REGION}"

    echo "   Waiting for deletion..."
    aws dynamodb wait table-not-exists --table-name "${LOCK_TABLE}" --region "${AWS_REGION}"

    echo -e "   ${GREEN}✓ DynamoDB table deleted${NC}"
else
    echo -e "   ${YELLOW}Table not found (already deleted?)${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Backend infrastructure has been removed."
echo ""
echo "To recreate it, run:"
echo "  ./scripts/setup-terraform-backend.sh"
echo ""
