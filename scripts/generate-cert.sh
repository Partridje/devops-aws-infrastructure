#!/bin/bash

# Generate self-signed SSL certificate for ALB
# For production, use AWS Certificate Manager (ACM) instead

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DOMAIN="${1:-demo.example.com}"
OUTPUT_DIR="${2:-.}"

echo -e "${GREEN}Generating self-signed SSL certificate...${NC}"
echo -e "${YELLOW}Domain: ${DOMAIN}${NC}"
echo -e "${YELLOW}Output directory: ${OUTPUT_DIR}${NC}"

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

# Generate private key
openssl genrsa -out "${OUTPUT_DIR}/private-key.pem" 2048

# Generate certificate signing request
openssl req -new -key "${OUTPUT_DIR}/private-key.pem" \
    -out "${OUTPUT_DIR}/csr.pem" \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN}"

# Generate self-signed certificate (valid for 1 year)
openssl x509 -req -days 365 \
    -in "${OUTPUT_DIR}/csr.pem" \
    -signkey "${OUTPUT_DIR}/private-key.pem" \
    -out "${OUTPUT_DIR}/certificate.pem"

# Clean up CSR
rm "${OUTPUT_DIR}/csr.pem"

echo -e "${GREEN}✓ Certificate generated successfully!${NC}"
echo -e "Files created:"
echo -e "  • Private Key: ${OUTPUT_DIR}/private-key.pem"
echo -e "  • Certificate: ${OUTPUT_DIR}/certificate.pem"
echo ""
echo -e "${YELLOW}To import to AWS ACM:${NC}"
echo -e "aws acm import-certificate \\"
echo -e "  --certificate fileb://${OUTPUT_DIR}/certificate.pem \\"
echo -e "  --private-key fileb://${OUTPUT_DIR}/private-key.pem \\"
echo -e "  --region <your-region>"
