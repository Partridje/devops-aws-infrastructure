# AWS WAF Setup Guide

This guide explains how to configure AWS WAF (Web Application Firewall) to protect your Application Load Balancer from common web attacks.

## Overview

AWS WAF is automatically deployed with the production infrastructure. It provides:
- **OWASP Top 10 protection** - SQL injection, XSS, CSRF, etc.
- **Known bad inputs protection** - Malicious patterns and exploits
- **IP reputation filtering** - Block known malicious IPs
- **Rate limiting** - Prevent DDoS and brute force attacks
- **Geo-blocking** (optional) - Block specific countries
- **IP whitelisting** (optional) - Trust specific IPs

**Cost**: ~$5-10/month base + $1 per million requests

---

## What's Protected

### AWS Managed Rules

Your ALB is protected by three AWS Managed Rule Sets:

1. **Core Rule Set (AWSManagedRulesCommonRuleSet)**
   - SQL injection attacks
   - Cross-site scripting (XSS)
   - Local file inclusion (LFI)
   - Remote file inclusion (RFI)
   - PHP injection
   - Path traversal
   - Session fixation
   - And more OWASP Top 10 vulnerabilities

2. **Known Bad Inputs (AWSManagedRulesKnownBadInputsRuleSet)**
   - Known malicious patterns
   - Invalid or malformed requests
   - Exploit attempts

3. **IP Reputation List (AWSManagedRulesAmazonIpReputationList)**
   - Known malicious IP addresses
   - Botnets and compromised hosts
   - Updated automatically by AWS

### Custom Rules

4. **Rate Limiting**
   - Default: 2000 requests per 5 minutes from single IP
   - Prevents DDoS, brute force, scraping
   - Adjustable based on your traffic patterns

---

## Default Configuration

The WAF is deployed with secure defaults for production:

```hcl
# Default settings (no configuration needed)
waf_rate_limit                = 2000       # 2000 req/5min per IP
waf_ip_whitelist              = []         # No whitelisted IPs
waf_blocked_countries         = []         # No countries blocked
waf_excluded_rules            = []         # All rules enabled
waf_blocked_requests_threshold = 1000      # CloudWatch alarm threshold
```

These defaults are suitable for most applications. Customize only if needed.

---

## Customization

### Adjusting Rate Limiting

If legitimate users are being rate-limited:

```hcl
# terraform/environments/prod/terraform.tfvars
waf_rate_limit = 5000  # Increase to 5000 requests per 5 minutes
```

**When to adjust:**
- API-heavy applications
- High traffic from single IPs (corporate networks, NAT gateways)
- Load testing

**Monitoring**: Check CloudWatch metric `RateLimitRule` for blocked requests.

### IP Whitelisting

Whitelist trusted IPs to bypass all WAF rules:

```hcl
# terraform/environments/prod/terraform.tfvars
waf_ip_whitelist = [
  "203.0.113.0/24",      # Office network
  "198.51.100.42/32",    # Monitoring service
  "192.0.2.0/24"         # Partner API
]
```

**Use cases:**
- Internal tools and monitoring
- CI/CD pipelines
- Trusted partner APIs
- Office networks for testing

⚠️ **Security warning**: Whitelisted IPs bypass ALL security rules. Use sparingly.

### Geo-Blocking

Block specific countries if your service doesn't operate there:

```hcl
# terraform/environments/prod/terraform.tfvars
waf_blocked_countries = ["CN", "RU", "KP"]  # China, Russia, North Korea
```

**Country codes**: ISO 3166-1 alpha-2 (2-letter codes)
- Full list: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2

⚠️ **Business warning**:
- Ensure you don't block legitimate customers
- Consider GDPR and other regulations
- Document business justification

### Excluding Specific Rules

If a legitimate request is blocked (false positive):

1. **Check WAF logs** to identify the rule:
   ```bash
   aws wafv2 get-sampled-requests \
     --web-acl-arn $(terraform output -raw waf_web_acl_arn) \
     --scope REGIONAL \
     --region eu-north-1 \
     --rule-metric-name demo-app-prod-common-rule-set \
     --max-items 100
   ```

2. **Add rule to exclusions** (sets rule to COUNT mode instead of BLOCK):
   ```hcl
   # terraform/environments/prod/terraform.tfvars
   waf_excluded_rules = [
     "SizeRestrictions_BODY",     # If you need large POST bodies
     "GenericRFI_BODY"            # If blocking legitimate file uploads
   ]
   ```

3. **Apply and test**:
   ```bash
   terraform apply
   # Test the previously blocked request
   ```

**Common exclusions:**
- `SizeRestrictions_BODY` - Large file uploads or API payloads
- `GenericRFI_BODY` - File uploads with URLs in body
- `EC2MetaDataSSRF_BODY` - If using EC2 metadata in requests (rare)

⚠️ **Security warning**: Only exclude rules after confirming false positives.

---

## Monitoring

### CloudWatch Metrics

WAF automatically publishes metrics to CloudWatch:

| Metric | Description | Normal Range |
|--------|-------------|--------------|
| `AllowedRequests` | Requests passed through | Varies by traffic |
| `BlockedRequests` | Requests blocked | Low (< 5% of total) |
| `CountedRequests` | Requests in COUNT mode | 0 (if no exclusions) |

**View metrics:**
```bash
# Via AWS Console
AWS Console → CloudWatch → Metrics → WAFV2

# Via CLI
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --dimensions Name=WebACL,Value=demo-app-prod-web-acl \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T23:59:59Z \
  --period 3600 \
  --statistics Sum \
  --region eu-north-1
```

### CloudWatch Alarms

Two alarms are automatically created:

1. **High Blocked Requests** (`demo-app-prod-waf-blocked-requests`)
   - **Condition**: > 1000 blocked requests in 5 minutes
   - **Meaning**: Potential attack or misconfiguration
   - **Action**:
     - Check WAF logs for attack patterns
     - Verify no false positives blocking legitimate users
     - Consider adjusting rules if needed

2. **Rate Limit Triggered** (`demo-app-prod-waf-rate-limit`)
   - **Condition**: > 100 requests blocked by rate limiting in 5 minutes
   - **Meaning**: DDoS attempt or legitimate user hitting limit
   - **Action**:
     - Check source IPs in WAF logs
     - If legitimate: increase `waf_rate_limit`
     - If attack: monitor and potentially add IP to permanent block list

**Email alerts**: Automatically sent to `alert_email_addresses` from terraform.tfvars.

### WAF Logs

WAF logs are stored in CloudWatch Logs:

**Log group**: `/aws/wafv2/demo-app-prod`

**View logs:**
```bash
# Via AWS Console
AWS Console → CloudWatch → Log Groups → /aws/wafv2/demo-app-prod

# Via CLI
aws logs tail /aws/wafv2/demo-app-prod --follow --region eu-north-1
```

**Log contents:**
- Request details (IP, URI, headers)
- Matched rules
- Action taken (ALLOW, BLOCK, COUNT)
- Timestamp

**Sensitive data**: Authorization headers and cookies are automatically redacted.

---

## Testing WAF

### Test Rate Limiting

```bash
# Get ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name)

# Send many requests quickly (should trigger rate limiting)
for i in {1..3000}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://${ALB_DNS}/health &
done
wait

# Check if requests were blocked (403 Forbidden)
# Check CloudWatch metrics for BlockedRequests
```

### Test SQL Injection Protection

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)

# This should be blocked by WAF
curl "https://${ALB_DNS}/api/items?id=1' OR '1'='1"

# Expected: 403 Forbidden
# Check WAF logs for: terminatingRuleId: GenericRFI_QUERYARGUMENTS
```

### Test XSS Protection

```bash
# This should be blocked by WAF
curl -X POST "https://${ALB_DNS}/api/items" \
  -H "Content-Type: application/json" \
  -d '{"name":"<script>alert(1)</script>"}'

# Expected: 403 Forbidden
# Check WAF logs for: terminatingRuleId: XSS_BODY
```

### Verify Whitelisted IP

```bash
# Add your current IP to whitelist in terraform.tfvars
MY_IP=$(curl -s ifconfig.me)
echo "waf_ip_whitelist = [\"${MY_IP}/32\"]" >> terraform.tfvars

# Apply changes
terraform apply

# Now SQL injection attempt should be ALLOWED (not recommended for prod!)
curl "https://${ALB_DNS}/api/items?id=1' OR '1'='1"

# Expected: Request reaches application (not blocked by WAF)
```

---

## Troubleshooting

### Legitimate Requests Being Blocked

**Problem**: Valid API requests or form submissions get 403 Forbidden

**Diagnosis**:
1. Check WAF logs:
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/wafv2/demo-app-prod \
     --filter-pattern "BLOCK" \
     --region eu-north-1
   ```

2. Identify the blocking rule:
   ```json
   {
     "terminatingRuleId": "GenericRFI_BODY",
     "action": "BLOCK"
   }
   ```

**Solutions**:
1. **Temporary**: Add rule to exclusions
   ```hcl
   waf_excluded_rules = ["GenericRFI_BODY"]
   ```

2. **Better**: Fix the request to not trigger the rule
   - Avoid suspicious patterns in URLs/bodies
   - URL-encode special characters
   - Use proper Content-Type headers

3. **Last resort**: Whitelist the source IP

### Rate Limiting Blocking Legitimate Users

**Problem**: Users getting 403 during normal usage

**Diagnosis**:
1. Check rate limit metrics:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/WAFV2 \
     --metric-name BlockedRequests \
     --dimensions Name=Rule,Value=RateLimitRule \
     --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 \
     --statistics Sum \
     --region eu-north-1
   ```

2. Check if legitimate users are hitting limit:
   ```bash
   # View sampled blocked requests
   aws wafv2 get-sampled-requests \
     --web-acl-arn $(terraform output -raw waf_web_acl_arn) \
     --rule-metric-name demo-app-prod-rate-limit \
     --scope REGIONAL \
     --max-items 100 \
     --region eu-north-1
   ```

**Solutions**:
1. **Increase rate limit**:
   ```hcl
   waf_rate_limit = 5000  # Or higher
   ```

2. **Whitelist corporate NAT gateway** (if many users behind one IP):
   ```hcl
   waf_ip_whitelist = ["203.0.113.0/24"]
   ```

3. **Implement application-level rate limiting** (more granular)

### WAF Not Blocking Malicious Requests

**Problem**: Attack requests are passing through WAF

**Diagnosis**:
1. Verify WAF is associated with ALB:
   ```bash
   aws wafv2 list-resources-for-web-acl \
     --web-acl-arn $(terraform output -raw waf_web_acl_arn) \
     --region eu-north-1
   ```

2. Check if rules are in COUNT mode (excluded):
   ```bash
   aws wafv2 get-web-acl \
     --id $(terraform output -raw waf_web_acl_id) \
     --scope REGIONAL \
     --region eu-north-1
   ```

**Solutions**:
1. Remove unnecessary exclusions:
   ```hcl
   waf_excluded_rules = []  # Remove all exclusions
   ```

2. Verify WAF logs show BLOCK actions:
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/wafv2/demo-app-prod \
     --filter-pattern "BLOCK" \
     --start-time $(date -u -d '10 minutes ago' +%s)000 \
     --region eu-north-1
   ```

### High WAF Costs

**Problem**: WAF costs higher than expected

**Typical costs**:
- Web ACL: $5/month
- Rules: $1/month per rule (5 rules = $5/month)
- Requests: $1 per million requests

**Cost analysis**:
```bash
# Check request volume
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name AllowedRequests \
  --dimensions Name=WebACL,Value=demo-app-prod-web-acl \
  --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum \
  --region eu-north-1
```

**Estimated monthly costs**:
- 10M requests: ~$10-15/month
- 100M requests: ~$20-25/month
- 1B requests: ~$110-120/month

**Cost reduction**:
- WAF is essential for production, cost is justified
- Consider removing geo-blocking if not needed (saves $1/month)
- Dev environment: WAF is optional (not deployed by default)

---

## Best Practices

### Security

✅ **DO:**
- Keep all AWS Managed Rules enabled by default
- Monitor WAF logs regularly for attack patterns
- Set up CloudWatch alarms for anomalies
- Test false positives in dev environment first
- Document any rule exclusions with justification
- Review and update WAF configuration quarterly

❌ **DON'T:**
- Disable WAF to "fix" false positives
- Whitelist large IP ranges without justification
- Exclude rules without understanding impact
- Ignore WAF blocking alerts
- Use same configuration for dev and prod

### Performance

✅ **DO:**
- WAF adds < 5ms latency (negligible)
- Use CloudFront with WAF for global performance
- Monitor ALB response times before/after WAF

❌ **DON'T:**
- WAF does not significantly impact performance
- No need to optimize unless seeing > 10ms latency

### Compliance

✅ **DO:**
- WAF helps with PCI DSS, HIPAA, SOC 2 compliance
- Document WAF configuration for audits
- Keep CloudWatch logs for required retention period
- Regular security reviews and penetration testing

---

## Advanced Configuration

### Custom Rules

Add custom rules in `terraform/modules/waf/main.tf`:

```hcl
# Example: Block specific user agents
resource "aws_wafv2_regex_pattern_set" "bad_bots" {
  name  = "${var.name_prefix}-bad-bots"
  scope = "REGIONAL"

  regular_expression {
    regex_string = "(?i)(bot|crawler|spider|scraper)"
  }
}

# Add rule to Web ACL
rule {
  name     = "BlockBadBots"
  priority = 6

  action {
    block {}
  }

  statement {
    regex_pattern_set_reference_statement {
      arn = aws_wafv2_regex_pattern_set.bad_bots.arn

      field_to_match {
        single_header {
          name = "user-agent"
        }
      }

      text_transformation {
        priority = 0
        type     = "NONE"
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-bad-bots"
    sampled_requests_enabled   = true
  }
}
```

### IP Set Management

Manage IP block lists separately:

```bash
# Create permanent block list
aws wafv2 create-ip-set \
  --name demo-app-prod-block-list \
  --scope REGIONAL \
  --ip-address-version IPV4 \
  --addresses "198.51.100.42/32" "203.0.113.0/24" \
  --region eu-north-1

# Update block list
aws wafv2 update-ip-set \
  --name demo-app-prod-block-list \
  --scope REGIONAL \
  --id <ip-set-id> \
  --addresses "198.51.100.42/32" "203.0.113.0/24" "192.0.2.100/32" \
  --lock-token <lock-token> \
  --region eu-north-1
```

### CloudFront Integration

For global applications, use WAF with CloudFront:

```hcl
# Create global WAF (scope: CLOUDFRONT)
resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us-east-1  # CloudFront WAF must be in us-east-1

  name  = "${var.name_prefix}-cloudfront-waf"
  scope = "CLOUDFRONT"

  # Same rules as regional WAF
  # ...
}

# Associate with CloudFront distribution
resource "aws_cloudfront_distribution" "main" {
  web_acl_id = aws_wafv2_web_acl.cloudfront.arn
  # ...
}
```

---

## WAF Rules Reference

### Core Rule Set Details

Full list of rules in `AWSManagedRulesCommonRuleSet`:

- **SQL Injection**: SQLi_QUERYARGUMENTS, SQLi_BODY, SQLi_COOKIE, SQLi_URIPATH
- **Cross-Site Scripting**: XSS_QUERYARGUMENTS, XSS_BODY, XSS_COOKIE, XSS_URIPATH
- **Size Restrictions**: SizeRestrictions_QUERYSTRING, SizeRestrictions_BODY
- **File Inclusion**: GenericRFI_QUERYARGUMENTS, GenericRFI_BODY, GenericLFI_QUERYSTRING
- **PHP Injection**: GenericPHPI_QUERYARGUMENTS, GenericPHPI_BODY
- **Path Traversal**: RestrictedExtensions_URIPATH, RestrictedExtensions_QUERYARGUMENTS
- **Session Fixation**: UserAgent_BadBots, NoUserAgent_HEADER

Full documentation: https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html

---

## Summary

**WAF is enabled by default in production** with these protections:
- ✅ OWASP Top 10 protection
- ✅ Known bad inputs blocking
- ✅ IP reputation filtering
- ✅ Rate limiting (2000 req/5min per IP)
- ✅ CloudWatch monitoring and alarms
- ✅ Detailed logging

**No action required** unless you need to:
- Increase rate limits for high-traffic applications
- Whitelist trusted IPs
- Block specific countries
- Exclude rules causing false positives

**Cost**: ~$5-10/month base + $1 per million requests (essential for production security)

---

**Related Documentation**:
- [HTTPS Setup Guide](./HTTPS_SETUP.md)
- [SNS Alerts Setup](./SNS_SETUP.md)
- [Main README](../README.md)

**AWS Documentation**:
- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/)
- [AWS Managed Rules](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups.html)
- [WAF Pricing](https://aws.amazon.com/waf/pricing/)
