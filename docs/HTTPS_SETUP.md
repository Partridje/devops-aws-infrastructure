# HTTPS/SSL Setup Guide

This guide explains how to configure HTTPS/SSL for the Application Load Balancer using AWS Certificate Manager (ACM).

## Overview

The infrastructure supports HTTPS out of the box. You only need to:
1. Create an SSL/TLS certificate
2. Update Terraform variables
3. Redeploy infrastructure

## Prerequisites

- **Domain name** (for production) or willingness to use self-signed certificate (for testing)
- **Route53 hosted zone** (optional, for automatic DNS validation)
- **AWS CLI** configured

---

## Option 1: AWS Certificate Manager (ACM) - Production

### Step 1: Request Certificate

#### Using AWS Console

1. Go to **AWS Certificate Manager** → **Request certificate**
2. Choose **Request a public certificate**
3. Enter domain names:
   - `example.com`
   - `*.example.com` (wildcard for subdomains)
4. Choose validation method:
   - **DNS validation** (recommended if you control DNS)
   - **Email validation** (alternative)
5. Add tags (optional)
6. Click **Request**

#### Using AWS CLI

```bash
# Request certificate
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names *.example.com \
  --validation-method DNS \
  --region eu-north-1

# Note the CertificateArn from output
```

### Step 2: Validate Certificate

#### DNS Validation (Recommended)

1. ACM will provide CNAME records
2. Add these CNAME records to your DNS provider
3. Wait for validation (usually 5-30 minutes)

**If using Route53:**

```bash
# ACM can automatically add DNS records to Route53
# Just approve in the ACM console
```

**If using external DNS provider:**

```bash
# Get validation records
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --region eu-north-1

# Add these CNAME records to your DNS provider:
# Name: _xxxxx.example.com
# Value: _yyyyy.acm-validations.aws.
```

#### Email Validation (Alternative)

1. ACM sends validation emails to:
   - admin@example.com
   - administrator@example.com
   - hostmaster@example.com
   - postmaster@example.com
   - webmaster@example.com
2. Click the validation link in the email

### Step 3: Get Certificate ARN

```bash
# List certificates
aws acm list-certificates --region eu-north-1

# Get full details
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --region eu-north-1
```

Copy the Certificate ARN (format: `arn:aws:acm:region:account:certificate/xxx`)

---

## Option 2: Self-Signed Certificate - Testing Only

**⚠️ WARNING:** Self-signed certificates are NOT suitable for production. Browsers will show security warnings.

### Step 1: Generate Self-Signed Certificate

```bash
# Generate private key
openssl genrsa -out private-key.pem 2048

# Generate certificate signing request (CSR)
openssl req -new -key private-key.pem -out csr.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=demo.example.com"

# Generate self-signed certificate (valid for 365 days)
openssl x509 -req -days 365 -in csr.pem \
  -signkey private-key.pem -out certificate.pem
```

### Step 2: Import to ACM

```bash
# Import self-signed certificate to ACM
aws acm import-certificate \
  --certificate fileb://certificate.pem \
  --private-key fileb://private-key.pem \
  --region eu-north-1

# Note the CertificateArn from output
```

### Step 3: Cleanup

```bash
# Remove private key from local machine (security)
rm -f private-key.pem csr.pem certificate.pem
```

---

## Step 4: Update Terraform Configuration

### Development Environment

Edit `terraform/environments/dev/terraform.tfvars`:

```hcl
# Add certificate ARN
certificate_arn = "arn:aws:acm:eu-north-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Optional: Enable HTTP to HTTPS redirect
# (Uncomment if you want to force HTTPS)
# enable_https_redirect = true
```

### Production Environment

Edit `terraform/environments/prod/terraform.tfvars`:

```hcl
# Add certificate ARN
certificate_arn = "arn:aws:acm:eu-north-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Enable HTTP to HTTPS redirect (recommended for production)
enable_https_redirect = true
```

---

## Step 5: Deploy Changes

```bash
cd terraform/environments/prod  # or dev

# Review changes
terraform plan

# Apply changes
terraform apply

# Get HTTPS URL
terraform output alb_url  # Will show https:// if certificate is configured
```

---

## Step 6: Verify HTTPS

```bash
# Get ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name)

# Test HTTPS endpoint
curl https://${ALB_DNS}/health

# Test HTTP redirect (if enabled)
curl -I http://${ALB_DNS}/  # Should return 301 redirect
```

---

## Configure DNS (Optional but Recommended)

### Using Route53

```bash
# Create A record pointing to ALB
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "<alb-hosted-zone-id>",
          "DNSName": "<alb-dns-name>",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

### Using External DNS Provider

Create an A record or CNAME:

- **Type**: A or CNAME
- **Name**: api.example.com
- **Value**: <alb-dns-name> (from terraform output)
- **TTL**: 300

---

## Security Best Practices

### 1. Certificate Renewal

ACM automatically renews certificates if using DNS validation:
- Renewal happens 60 days before expiration
- No action required for DNS-validated certificates
- Email-validated certificates require manual renewal

### 2. SSL/TLS Policy

The default SSL policy is `ELBSecurityPolicy-TLS-1-2-2017-01`.

To use a more secure policy, update `terraform/environments/*/terraform.tfvars`:

```hcl
ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"  # TLS 1.3 only
```

Available policies:
- `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.3 only, most secure)
- `ELBSecurityPolicy-TLS-1-2-2017-01` (TLS 1.2+, default)
- `ELBSecurityPolicy-2016-08` (TLS 1.0+, legacy)

### 3. HSTS (HTTP Strict Transport Security)

Add HSTS header to your application responses:

```python
# In Flask app
@app.after_request
def set_hsts_header(response):
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    return response
```

### 4. Certificate Monitoring

Set up CloudWatch alarm for certificate expiration:

```bash
# Create SNS topic for cert expiration alerts
aws sns create-topic --name certificate-expiration-alerts

# Subscribe to topic
aws sns subscribe \
  --topic-arn <topic-arn> \
  --protocol email \
  --notification-endpoint your-email@example.com
```

---

## Troubleshooting

### Certificate Validation Stuck

**Problem**: Certificate stuck in "Pending validation"

**Solutions**:
1. **DNS validation**: Verify CNAME records are correct
   ```bash
   dig _xxxxx.example.com CNAME
   ```
2. **Email validation**: Check spam folder for validation email
3. **Wait**: DNS propagation can take up to 30 minutes

### Certificate Not Found Error

**Problem**: `InvalidCertificateArn` or certificate not found

**Solutions**:
1. Verify certificate ARN is correct
2. Ensure certificate is in the same region as ALB (`eu-north-1`)
3. Check certificate status is "Issued":
   ```bash
   aws acm describe-certificate --certificate-arn <arn> --region eu-north-1
   ```

### Browser Shows "Not Secure"

**Problem**: Browser shows security warning

**Possible causes**:
1. **Self-signed certificate**: This is expected behavior. Click "Advanced" → "Proceed anyway" (testing only)
2. **Domain mismatch**: Certificate CN/SAN doesn't match domain name
3. **Expired certificate**: Check expiration date
4. **Mixed content**: Page loading HTTP resources over HTTPS

### HTTP Not Redirecting to HTTPS

**Problem**: HTTP requests don't redirect to HTTPS

**Solutions**:
1. Verify `enable_https_redirect = true` in terraform.tfvars
2. Check listener rules:
   ```bash
   aws elbv2 describe-listeners --load-balancer-arn <alb-arn>
   ```
3. Redeploy infrastructure:
   ```bash
   terraform apply
   ```

---

## Cost Considerations

### ACM Certificates

- **Public certificates**: FREE (no charge)
- **Private certificates**: $400/month per private CA + $0.75/month per certificate

### Data Transfer

- HTTPS uses same ALB pricing as HTTP
- Slight increase in CPU usage for SSL/TLS termination (negligible)

---

## Additional Resources

- [AWS Certificate Manager Documentation](https://docs.aws.amazon.com/acm/)
- [ALB HTTPS Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html)
- [SSL Labs Server Test](https://www.ssllabs.com/ssltest/) - Test your SSL configuration
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/) - Generate secure SSL configs

---

## Summary Checklist

- [ ] Certificate created in ACM
- [ ] Certificate validated and issued
- [ ] Certificate ARN copied
- [ ] `terraform.tfvars` updated with certificate_arn
- [ ] (Optional) `enable_https_redirect = true` configured
- [ ] Infrastructure redeployed with `terraform apply`
- [ ] HTTPS endpoint tested
- [ ] DNS records configured (if applicable)
- [ ] Browser shows secure padlock icon
- [ ] Certificate expiration monitoring configured

---

**Need help?** Open an issue or consult the main [README.md](../README.md) troubleshooting section.
