#!/bin/bash

# Setup GitHub OIDC Provider for AWS
# This allows GitHub Actions to authenticate with AWS without static credentials

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

GITHUB_ORG="${1}"
GITHUB_REPO="${2}"
AWS_REGION="${3:-eu-north-1}"

if [ -z "${GITHUB_ORG}" ] || [ -z "${GITHUB_REPO}" ]; then
    echo -e "${RED}Usage: $0 <github-org> <github-repo> [aws-region]${NC}"
    echo -e "Example: $0 myorg myrepo eu-north-1"
    exit 1
fi

echo -e "${GREEN}Setting up GitHub OIDC for AWS...${NC}"
echo -e "${YELLOW}GitHub Org: ${GITHUB_ORG}${NC}"
echo -e "${YELLOW}GitHub Repo: ${GITHUB_REPO}${NC}"
echo -e "${YELLOW}AWS Region: ${AWS_REGION}${NC}"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}AWS credentials are not configured${NC}"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ AWS Account: ${AWS_ACCOUNT_ID}${NC}"

# Create OIDC provider
echo -e "${GREEN}Creating GitHub OIDC provider...${NC}"

THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com" &> /dev/null; then
    echo -e "${YELLOW}✓ OIDC provider already exists${NC}"
else
    aws iam create-open-id-connect-provider \
        --url "https://token.actions.githubusercontent.com" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "${THUMBPRINT}"
    echo -e "${GREEN}✓ OIDC provider created${NC}"
fi

# Create IAM role for GitHub Actions
echo -e "${GREEN}Creating IAM role for GitHub Actions...${NC}"

ROLE_NAME="github-actions-terraform-role"

cat > /tmp/trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
                }
            }
        }
    ]
}
EOF

if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
    echo -e "${YELLOW}✓ Role ${ROLE_NAME} already exists, updating trust policy...${NC}"
    aws iam update-assume-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-document file:///tmp/trust-policy.json
else
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "Role for GitHub Actions to manage Terraform infrastructure"
    echo -e "${GREEN}✓ Role ${ROLE_NAME} created${NC}"
fi

rm /tmp/trust-policy.json

# Attach policies to role
echo -e "${GREEN}Attaching policies to role...${NC}"

# For full Terraform access, you might want to use AdministratorAccess
# For production, create a custom policy with minimal required permissions
aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}✓ Policies attached${NC}"

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}GitHub OIDC Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Add these secrets to your GitHub repository:"
echo -e "  • ${YELLOW}AWS_REGION${NC}: ${AWS_REGION}"
echo -e "  • ${YELLOW}AWS_ACCOUNT_ID${NC}: ${AWS_ACCOUNT_ID}"
echo -e "  • ${YELLOW}AWS_ROLE_ARN${NC}: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo -e "In your GitHub Actions workflow, configure AWS credentials:"
echo ""
echo -e "${YELLOW}- name: Configure AWS credentials${NC}"
echo -e "${YELLOW}  uses: aws-actions/configure-aws-credentials@v4${NC}"
echo -e "${YELLOW}  with:${NC}"
echo -e "${YELLOW}    role-to-assume: \${{ secrets.AWS_ROLE_ARN }}${NC}"
echo -e "${YELLOW}    aws-region: \${{ secrets.AWS_REGION }}${NC}"
echo ""
echo -e "${RED}WARNING: The role has AdministratorAccess for demo purposes.${NC}"
echo -e "${RED}For production, create a custom policy with minimal permissions.${NC}"
