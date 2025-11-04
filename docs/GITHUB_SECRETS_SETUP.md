# GitHub Secrets Setup

## Setting Up Secrets for Production

### 1. Alert Email Addresses

SNS email notifications require configuration through GitHub Secret.

**Steps**:

1. Open repository settings:
   ```
   https://github.com/Partridje/devops-aws-infrastructure/settings/secrets/actions
   ```

2. Click **"New repository secret"**

3. Add secret:
   - **Name**: `ALERT_EMAIL_ADDRESSES`
   - **Value**: `["your-email@example.com"]`

   Format: JSON array of strings. For multiple emails:
   ```json
   ["email1@example.com","email2@example.com"]
   ```

4. Click **"Add secret"**

### 2. Verification

After adding the secret:

1. Run terraform apply through GitHub Actions:
   ```bash
   # Through UI: Actions → Terraform Apply → Run workflow (prod)
   # Or through CLI:
   gh workflow run terraform-apply.yml -f environment=prod
   ```

2. Verify that SNS subscription was created:
   ```bash
   aws sns list-subscriptions-by-topic \
     --topic-arn arn:aws:sns:eu-north-1:851725636341:demo-app-prod-prod-alarms \
     --region eu-north-1
   ```

3. Check email `your-email@example.com`:
   - You should receive an email "AWS Notification - Subscription Confirmation"
   - Click **"Confirm subscription"**

4. After confirmation check the status:
   ```bash
   aws sns list-subscriptions-by-topic \
     --topic-arn arn:aws:sns:eu-north-1:851725636341:demo-app-prod-prod-alarms \
     --region eu-north-1 \
     --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' \
     --output table
   ```

   Status should be **Confirmed** (not PendingConfirmation).

### 3. Testing Notifications

Verify that email notifications work:

```bash
# Force activate alarm (create high CPU load)
# See docs/TESTING_GUIDE.md section "1.1 CPU-Based Scaling Test"

# Or publish a test message
aws sns publish \
  --topic-arn arn:aws:sns:eu-north-1:851725636341:demo-app-prod-prod-alarms \
  --subject "Test Alert" \
  --message "This is a test notification from demo-app-prod" \
  --region eu-north-1
```

You should receive an email.

## Existing Secrets

| Secret Name | Description | Format |
|-------------|----------|--------|
| `AWS_ROLE_ARN` | IAM Role for OIDC | `arn:aws:iam::...` |
| `ALERT_EMAIL_ADDRESSES` | Email for alerts | JSON array |

## Troubleshooting

### Secret not being picked up

If after adding the secret terraform apply doesn't create subscription:

1. Verify that the secret exists:
   ```bash
   gh secret list
   ```

2. Verify that workflow uses the secret (`.github/workflows/terraform-apply.yml`):
   ```yaml
   env:
     TF_VAR_alert_email_addresses: ${{ secrets.ALERT_EMAIL_ADDRESSES }}
   ```

3. Check GitHub Actions logs:
   ```bash
   gh run list --workflow=terraform-apply.yml --limit 1
   gh run view <run-id> --log
   ```

### Email not arriving

1. Check spam folder
2. Verify that subscription is in "Confirmed" state:
   ```bash
   aws sns list-subscriptions --region eu-north-1 | grep -A 5 tcytcerov
   ```
3. Check SNS topic policy:
   ```bash
   aws sns get-topic-attributes \
     --topic-arn arn:aws:sns:eu-north-1:851725636341:demo-app-prod-prod-alarms \
     --region eu-north-1
   ```

### Changing email address

1. Update GitHub Secret:
   ```
   https://github.com/Partridje/devops-aws-infrastructure/settings/secrets/actions/ALERT_EMAIL_ADDRESSES
   ```

2. Run terraform apply:
   ```bash
   gh workflow run terraform-apply.yml -f environment=prod
   ```

3. Terraform will remove old subscription and create a new one
4. Confirm the new email

## Security Notes

- ❌ **DO NOT commit** email addresses in terraform.tfvars
- ✅ **USE** GitHub Secrets for sensitive data
- ✅ **VERIFY** that `.tfvars` with real emails is in `.gitignore`
- ✅ **DOCUMENT** which secrets are needed in README

## Additional Secrets (if needed)

If additional secrets are needed in the future:

```bash
# SSL Certificate ARN
TF_VAR_certificate_arn="arn:aws:acm:..."

# WAF IP Whitelist
TF_VAR_waf_ip_whitelist='["1.2.3.4/32","5.6.7.8/32"]'

# Custom domain
TF_VAR_domain_name="app.example.com"
```

Add them similarly through GitHub Settings → Secrets.
