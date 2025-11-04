# GitHub Secrets Setup

## Настройка Secrets для Production

### 1. Alert Email Addresses

SNS email уведомления требуют настройки через GitHub Secret.

**Шаги**:

1. Открой настройки репозитория:
   ```
   https://github.com/Partridje/devops-aws-infrastructure/settings/secrets/actions
   ```

2. Нажми **"New repository secret"**

3. Добавь secret:
   - **Name**: `ALERT_EMAIL_ADDRESSES`
   - **Value**: `["tcytcerov@gmail.com"]`

   Формат: JSON массив строк. Для нескольких email:
   ```json
   ["email1@example.com","email2@example.com"]
   ```

4. Нажми **"Add secret"**

### 2. Проверка работы

После добавления secret:

1. Запусти terraform apply через GitHub Actions:
   ```bash
   # Через UI: Actions → Terraform Apply → Run workflow (prod)
   # Или через CLI:
   gh workflow run terraform-apply.yml -f environment=prod
   ```

2. Проверь что SNS subscription создалась:
   ```bash
   aws sns list-subscriptions-by-topic \
     --topic-arn arn:aws:sns:eu-north-1:851725636341:demo-app-prod-prod-alarms \
     --region eu-north-1
   ```

3. Проверь email `tcytcerov@gmail.com`:
   - Должно прийти письмо "AWS Notification - Subscription Confirmation"
   - Нажми **"Confirm subscription"**

4. После подтверждения проверь статус:
   ```bash
   aws sns list-subscriptions-by-topic \
     --topic-arn arn:aws:sns:eu-north-1:851725636341:demo-app-prod-prod-alarms \
     --region eu-north-1 \
     --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' \
     --output table
   ```

   Должен быть статус **Confirmed** (не PendingConfirmation).

### 3. Тестирование уведомлений

Проверь что email уведомления работают:

```bash
# Принудительно активировать alarm (создать высокую CPU нагрузку)
# См. docs/TESTING_GUIDE.md раздел "1.1 CPU-Based Scaling Test"

# Или опубликовать тестовое сообщение
aws sns publish \
  --topic-arn arn:aws:sns:eu-north-1:851725636341:demo-app-prod-prod-alarms \
  --subject "Test Alert" \
  --message "This is a test notification from demo-app-prod" \
  --region eu-north-1
```

Должно прийти письмо на email.

## Существующие Secrets

| Secret Name | Описание | Формат |
|-------------|----------|--------|
| `AWS_ROLE_ARN` | IAM Role для OIDC | `arn:aws:iam::...` |
| `ALERT_EMAIL_ADDRESSES` | Email для alerts | JSON array |

## Troubleshooting

### Secret не подхватывается

Если после добавления secret terraform apply не создает subscription:

1. Проверь что secret существует:
   ```bash
   gh secret list
   ```

2. Проверь что workflow использует secret (`.github/workflows/terraform-apply.yml`):
   ```yaml
   env:
     TF_VAR_alert_email_addresses: ${{ secrets.ALERT_EMAIL_ADDRESSES }}
   ```

3. Проверь логи GitHub Actions:
   ```bash
   gh run list --workflow=terraform-apply.yml --limit 1
   gh run view <run-id> --log
   ```

### Email не приходит

1. Проверь spam folder
2. Проверь что subscription в состоянии "Confirmed":
   ```bash
   aws sns list-subscriptions --region eu-north-1 | grep -A 5 tcytcerov
   ```
3. Проверь SNS topic policy:
   ```bash
   aws sns get-topic-attributes \
     --topic-arn arn:aws:sns:eu-north-1:851725636341:demo-app-prod-prod-alarms \
     --region eu-north-1
   ```

### Изменить email адрес

1. Обнови GitHub Secret:
   ```
   https://github.com/Partridje/devops-aws-infrastructure/settings/secrets/actions/ALERT_EMAIL_ADDRESSES
   ```

2. Запусти terraform apply:
   ```bash
   gh workflow run terraform-apply.yml -f environment=prod
   ```

3. Terraform удалит старую подписку и создаст новую
4. Подтверди новый email

## Security Notes

- ❌ **НЕ коммить** email адреса в terraform.tfvars
- ✅ **ИСПОЛЬЗУЙ** GitHub Secrets для чувствительных данных
- ✅ **ПРОВЕРЯЙ** что `.tfvars` с реальными email в `.gitignore`
- ✅ **ДОКУМЕНТИРУЙ** какие secrets нужны в README

## Дополнительные Secrets (при необходимости)

Если в будущем понадобятся дополнительные secrets:

```bash
# SSL Certificate ARN
TF_VAR_certificate_arn="arn:aws:acm:..."

# WAF IP Whitelist
TF_VAR_waf_ip_whitelist='["1.2.3.4/32","5.6.7.8/32"]'

# Custom domain
TF_VAR_domain_name="app.example.com"
```

Добавляй их аналогично через GitHub Settings → Secrets.
