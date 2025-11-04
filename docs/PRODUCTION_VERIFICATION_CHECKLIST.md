# Production Verification Checklist

Последовательный список проверок для верификации production инфраструктуры.

## Подготовка

```bash
# Установить переменные окружения
export AWS_REGION=eu-north-1
export ENV=prod
export ALB_URL="demo-app-prod-alb-619878086.eu-north-1.elb.amazonaws.com"

# Получить ASG имя
export ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `prod`)].AutoScalingGroupName' \
  --output text)

# Получить DB instance ID
export DB_INSTANCE=$(aws rds describe-db-instances \
  --region $AWS_REGION \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `prod`)].DBInstanceIdentifier' \
  --output text)

echo "ASG_NAME: $ASG_NAME"
echo "DB_INSTANCE: $DB_INSTANCE"
```

---

## 1. Базовые проверки инфраструктуры

### 1.1 Проверка VPC и Networking

```bash
# ✓ VPC существует
aws ec2 describe-vpcs \
  --region $AWS_REGION \
  --filters "Name=tag:Project,Values=demo-app" "Name=tag:Environment,Values=prod" \
  --query 'Vpcs[].[VpcId,CidrBlock,State]' \
  --output table

# ✓ 3 Availability Zones
aws ec2 describe-subnets \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" \
  --query 'Subnets[?contains(Tags[?Key==`Name`].Value, `public`)].AvailabilityZone' \
  --output text | wc -w

# ✓ NAT Gateways работают
aws ec2 describe-nat-gateways \
  --region $AWS_REGION \
  --filter "Name=tag:Environment,Values=prod" \
  --query 'NatGateways[].[NatGatewayId,State,SubnetId]' \
  --output table
```

**Ожидаемый результат:**
- 1 VPC в состоянии `available`
- 3 Availability Zones
- 3 NAT Gateways в состоянии `available`

---

### 1.2 Проверка EC2 Instances

```bash
# ✓ Инстансы запущены
aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Placement.AvailabilityZone,PrivateIpAddress]' \
  --output table

# ✓ Количество инстансов соответствует desired capacity
INSTANCE_COUNT=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text | wc -w)

echo "Running instances: $INSTANCE_COUNT (expected: 2)"
```

**Ожидаемый результат:**
- 2 инстанса типа `t3.small`
- Состояние `running`
- Распределены по разным AZ

---

### 1.3 Проверка Auto Scaling Group

```bash
# ✓ ASG конфигурация
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize,HealthCheckType,HealthCheckGracePeriod]' \
  --output table

# ✓ Scaling policies
aws autoscaling describe-policies \
  --auto-scaling-group-name $ASG_NAME \
  --region $AWS_REGION \
  --query 'ScalingPolicies[].[PolicyName,PolicyType,Enabled]' \
  --output table
```

**Ожидаемый результат:**
- MinSize: 2, DesiredCapacity: 2, MaxSize: 6
- HealthCheckType: `ELB`
- 2 scaling policies (CPU и ALB)

---

### 1.4 Проверка RDS

```bash
# ✓ RDS статус
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].[DBInstanceStatus,MultiAZ,DBInstanceClass,AllocatedStorage,BackupRetentionPeriod,DeletionProtection]' \
  --output table

# ✓ Automated backups
aws rds describe-db-snapshots \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --snapshot-type automated \
  --query 'DBSnapshots[].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table | head -10
```

**Ожидаемый результат:**
- Status: `available`
- MultiAZ: `True`
- Instance class: `db.t3.small`
- Backup retention: 30 days
- DeletionProtection: `True`
- Automated snapshots существуют

---

## 2. Проверка приложения

### 2.1 Health Check

```bash
# ✓ Health endpoint отвечает
curl -s http://$ALB_URL/health | jq .

# ✓ Версия приложения
VERSION=$(curl -s http://$ALB_URL/health | jq -r '.version')
echo "Application version: $VERSION (expected: 1.0.0)"

# ✓ Database статус
DB_STATUS=$(curl -s http://$ALB_URL/health | jq -r '.checks.database')
echo "Database status: $DB_STATUS (expected: ok или not_initialized)"
```

**Ожидаемый результат:**
- HTTP 200
- Status: `healthy`
- Version: `1.0.0`
- Database: connected

---

### 2.2 Application Endpoints

```bash
# ✓ Root endpoint
echo "Testing root endpoint..."
curl -s http://$ALB_URL/ | jq .

# ✓ Database endpoint
echo "Testing database endpoint..."
curl -s http://$ALB_URL/db | jq .

# ✓ API endpoint
echo "Testing API endpoint..."
curl -s http://$ALB_URL/api/items | jq .

# ✓ Создание записи
echo "Creating test item..."
curl -X POST http://$ALB_URL/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"test-item","value":123}' | jq .

# ✓ Проверка что запись создалась
curl -s http://$ALB_URL/api/items | jq .
```

**Ожидаемый результат:**
- Все endpoints возвращают HTTP 200
- Database connection работает
- CRUD операции работают

---

### 2.3 Load Balancer Health

```bash
# ✓ Target Group health
TG_ARN=$(aws elbv2 describe-target-groups \
  --region $AWS_REGION \
  --query "TargetGroups[?contains(TargetGroupName, 'demo-a')].TargetGroupArn" \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $AWS_REGION \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table

# ✓ Unhealthy targets
UNHEALTHY=$(aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $AWS_REGION \
  --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`]' \
  --output json)

if [ "$UNHEALTHY" == "[]" ]; then
  echo "✓ All targets are healthy"
else
  echo "✗ Some targets are unhealthy:"
  echo $UNHEALTHY | jq .
fi
```

**Ожидаемый результат:**
- Все targets в состоянии `healthy`
- Нет unhealthy targets

---

## 3. Мониторинг и алерты

### 3.1 SNS Email Subscription

```bash
# ✓ Subscription создан
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:$AWS_REGION:851725636341:demo-app-prod-prod-alarms \
  --region $AWS_REGION \
  --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' \
  --output table

# Проверь статус
SUBSCRIPTION_STATUS=$(aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:$AWS_REGION:851725636341:demo-app-prod-prod-alarms \
  --region $AWS_REGION \
  --query 'Subscriptions[0].SubscriptionArn' \
  --output text)

if [[ "$SUBSCRIPTION_STATUS" == *"PendingConfirmation"* ]]; then
  echo "⚠️  Email subscription pending confirmation"
  echo "Check email: tcytcerov@gmail.com"
else
  echo "✓ Email subscription confirmed"
fi
```

**Действие:** Если PendingConfirmation - подтверди email!

---

### 3.2 CloudWatch Alarms

```bash
# ✓ Список алармов
aws cloudwatch describe-alarms \
  --region $AWS_REGION \
  --alarm-name-prefix demo-app-prod \
  --query 'MetricAlarms[].[AlarmName,StateValue,ActionsEnabled]' \
  --output table

# ✓ Алармы в состоянии OK
ALARM_COUNT=$(aws cloudwatch describe-alarms \
  --region $AWS_REGION \
  --alarm-name-prefix demo-app-prod \
  --state-value ALARM \
  --query 'MetricAlarms[].AlarmName' \
  --output text | wc -w)

if [ "$ALARM_COUNT" -eq 0 ]; then
  echo "✓ No alarms in ALARM state"
else
  echo "⚠️  $ALARM_COUNT alarms in ALARM state:"
  aws cloudwatch describe-alarms \
    --region $AWS_REGION \
    --alarm-name-prefix demo-app-prod \
    --state-value ALARM \
    --query 'MetricAlarms[].[AlarmName,StateReason]' \
    --output table
fi
```

**Ожидаемый результат:**
- 10+ алармов создано
- Все в состоянии `OK`
- ActionsEnabled: `true`

---

### 3.3 CloudWatch Logs

```bash
# ✓ Log groups существуют
aws logs describe-log-groups \
  --region $AWS_REGION \
  --log-group-name-prefix "/aws" \
  --query 'logGroups[?contains(logGroupName, `demo-app-prod`)].logGroupName' \
  --output table

# ✓ Логи пишутся
echo "Recent application logs:"
aws logs tail /aws/ec2/demo-app-prod-application \
  --region $AWS_REGION \
  --since 5m \
  --format short | tail -20

# ✓ Проверка на ERROR
ERROR_COUNT=$(aws logs filter-log-events \
  --region $AWS_REGION \
  --log-group-name /aws/ec2/demo-app-prod-application \
  --filter-pattern "ERROR" \
  --start-time $(($(date +%s) - 3600))000 \
  --query 'events[].message' \
  --output text | wc -l)

echo "Errors in last hour: $ERROR_COUNT"
```

**Ожидаемый результат:**
- 3 log groups: application, RDS, VPC flow logs
- Логи пишутся в реальном времени
- Минимум ERROR логов

---

### 3.4 CloudWatch Dashboard

```bash
# ✓ Dashboard существует
aws cloudwatch list-dashboards \
  --region $AWS_REGION \
  --query 'DashboardEntries[?contains(DashboardName, `prod`)].[DashboardName]' \
  --output table

# Получить URL
DASHBOARD_URL="https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards/dashboard/demo-app-prod-prod-dashboard"
echo "Dashboard URL: $DASHBOARD_URL"
```

---

## 4. Безопасность

### 4.1 WAF Protection

```bash
# ✓ WAF Web ACL создан
aws wafv2 list-web-acls \
  --region $AWS_REGION \
  --scope REGIONAL \
  --query 'WebACLs[?contains(Name, `prod`)].[Name,Id]' \
  --output table

# ✓ WAF rules
WAF_ID=$(aws wafv2 list-web-acls \
  --region $AWS_REGION \
  --scope REGIONAL \
  --query 'WebACLs[?contains(Name, `prod`)].Id' \
  --output text)

aws wafv2 get-web-acl \
  --region $AWS_REGION \
  --scope REGIONAL \
  --id $WAF_ID \
  --query 'WebACL.Rules[].[Name,Priority]' \
  --output table

# ✓ WAF metrics
aws cloudwatch get-metric-statistics \
  --region $AWS_REGION \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --dimensions Name=WebACL,Value=demo-app-prod-web-acl Name=Region,Value=$AWS_REGION Name=Rule,Value=ALL \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --query 'Datapoints[0].Sum'
```

**Ожидаемый результат:**
- WAF активен
- 5-6 правил настроены
- BlockedRequests метрика доступна

---

### 4.2 Security Groups

```bash
# ✓ Security groups
aws ec2 describe-security-groups \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" \
  --query 'SecurityGroups[].[GroupName,GroupId]' \
  --output table

# ✓ ALB security group (80, 443)
ALB_SG=$(aws ec2 describe-security-groups \
  --region $AWS_REGION \
  --filters "Name=tag:Name,Values=*alb*" "Name=tag:Environment,Values=prod" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

aws ec2 describe-security-groups \
  --region $AWS_REGION \
  --group-ids $ALB_SG \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,ToPort,IpRanges[0].CidrIp]' \
  --output table
```

**Ожидаемый результат:**
- 3 security groups: ALB, Application, RDS
- ALB: открыт 80 (443 если есть certificate)
- Application: доступ только от ALB
- RDS: доступ только от Application SG

---

### 4.3 Secrets Manager

```bash
# ✓ Secrets существуют
aws secretsmanager list-secrets \
  --region $AWS_REGION \
  --query 'SecretList[?contains(Name, `prod`)].[Name,ARN]' \
  --output table

# ✓ Rotation enabled (если настроено)
aws secretsmanager describe-secret \
  --secret-id demo-app-prod-db-creds \
  --region $AWS_REGION \
  --query '[RotationEnabled,RotationRules]' \
  --output table
```

---

## 5. Функциональное тестирование

### 5.1 Rate Limiting Test (WAF)

```bash
echo "Testing WAF rate limiting (sending 100 rapid requests)..."

# Отправить много запросов быстро
for i in {1..100}; do
  curl -s -o /dev/null -w "%{http_code}\n" http://$ALB_URL/ &
done
wait

sleep 2

# Проверить что WAF блокирует
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_URL/)
if [ "$HTTP_CODE" == "403" ]; then
  echo "✓ WAF rate limiting works (got 403)"
else
  echo "⚠️  Got $HTTP_CODE (expected 403 after rate limit)"
fi

# Подождать 5 минут для снятия блокировки
echo "Waiting 5 minutes for rate limit to reset..."
```

**Ожидаемый результат:** После ~2000 запросов получаем 403

---

### 5.2 Multi-AZ Distribution Test

```bash
# ✓ Инстансы в разных AZ
echo "Checking instance distribution across AZs..."

aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone]' \
  --output table

# Делаем запросы и смотрим из каких AZ отвечают
echo "Making 20 requests to check AZ distribution..."
for i in {1..20}; do
  curl -s http://$ALB_URL/health | jq -r '.instance.az'
done | sort | uniq -c
```

**Ожидаемый результат:** Запросы распределяются между разными AZ

---

### 5.3 Database Connection Pool Test

```bash
# ✓ Connection pool работает
for i in {1..10}; do
  echo "Request $i:"
  curl -s http://$ALB_URL/db | jq '.pool_size'
done

# Все должны показывать pool_size: 10
```

---

### 5.4 Performance Test

```bash
# ✓ Response time
echo "Measuring response times (10 requests)..."

for i in {1..10}; do
  curl -o /dev/null -s -w "Response time: %{time_total}s\n" http://$ALB_URL/health
done

# ✓ CloudWatch ALB latency
aws cloudwatch get-metric-statistics \
  --region $AWS_REGION \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=app/demo-app-prod-alb/* \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  --query 'Datapoints[].[Timestamp,Average,Maximum]' \
  --output table
```

**Ожидаемый результат:** Response time < 200ms

---

## 6. Auto Scaling Test

### 6.1 Manual Scaling Test

```bash
echo "Current ASG configuration:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' \
  --output table

# Увеличить до 4
echo "Scaling up to 4 instances..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 4 \
  --region $AWS_REGION

echo "Waiting for instances to launch..."
sleep 60

# Проверить
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,HealthStatus,LifecycleState]' \
  --output table

# Вернуть обратно
echo "Scaling back to 2 instances..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 2 \
  --region $AWS_REGION
```

**Ожидаемый результат:** ASG масштабируется до 4, затем обратно до 2

---

### 6.2 CPU-Based Scaling (Опционально, создает нагрузку!)

```bash
echo "⚠️  This will create high CPU load!"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Skipped"
  exit 0
fi

# Получить instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo "Connecting to $INSTANCE_ID via SSM..."
echo "Run on instance: stress --cpu 4 --timeout 300s"
echo ""
echo "Then monitor scaling in another terminal:"
echo "watch -n 10 'aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region $AWS_REGION --query \"AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]\" --output text'"

# Открыть SSM session
aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION
```

---

## 7. Test Email Notifications

### 7.1 Отправить тестовое уведомление

```bash
# После подтверждения email subscription
echo "Sending test notification..."
aws sns publish \
  --topic-arn arn:aws:sns:$AWS_REGION:851725636341:demo-app-prod-prod-alarms \
  --subject "Test Alert from Production" \
  --message "This is a test notification from production infrastructure. If you receive this, email alerts are working correctly!" \
  --region $AWS_REGION

echo "✓ Test notification sent. Check email: tcytcerov@gmail.com"
```

**Ожидаемый результат:** Email приходит в течение 1 минуты

---

## 8. Disaster Recovery Test (ОСТОРОЖНО!)

### 8.1 Terminate Instance (симуляция отказа)

```bash
echo "⚠️  This will terminate 1 instance to simulate failure!"
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Skipped"
  exit 0
fi

# Терминировать 1 инстанс
INSTANCE_ID=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo "Terminating $INSTANCE_ID..."
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $AWS_REGION

# Проверить что приложение доступно
echo "Checking application availability..."
for i in {1..10}; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_URL/health)
  echo "Request $i: HTTP $HTTP_CODE"
  sleep 2
done

# ASG должен запустить новый инстанс
echo "Waiting for ASG to launch replacement..."
sleep 60

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,HealthStatus,LifecycleState]' \
  --output table
```

**Ожидаемый результат:**
- Приложение остается доступным (zero downtime)
- ASG автоматически запускает замену
- Через 2-3 минуты capacity восстановлен

---

## Summary Checklist

Отметь выполненные проверки:

**Инфраструктура:**
- [ ] VPC и Networking (3 AZ, NAT Gateways)
- [ ] EC2 Instances (2 running, t3.small)
- [ ] Auto Scaling Group (min=2, max=6, policies enabled)
- [ ] RDS (Multi-AZ, backups enabled)

**Приложение:**
- [ ] Health check работает
- [ ] Все endpoints отвечают (/, /health, /db, /api/items)
- [ ] Database connection работает
- [ ] CRUD операции работают
- [ ] Load Balancer targets healthy

**Мониторинг:**
- [ ] SNS email subscription confirmed
- [ ] CloudWatch alarms в состоянии OK
- [ ] CloudWatch Logs пишутся
- [ ] Dashboard доступен
- [ ] Test email notification received

**Безопасность:**
- [ ] WAF активен и работает
- [ ] Rate limiting срабатывает
- [ ] Security groups настроены правильно
- [ ] Secrets Manager работает

**Функциональность:**
- [ ] Multi-AZ distribution работает
- [ ] Database connection pool работает
- [ ] Performance приемлемый (< 200ms)

**Auto Scaling:**
- [ ] Manual scaling работает
- [ ] Instance termination recovery работает

**Disaster Recovery:**
- [ ] Instance failure recovery протестирован
- [ ] Zero downtime подтвержден

---

## Финальная проверка

```bash
echo "=== Production Infrastructure Status ==="
echo ""
echo "Application: http://$ALB_URL"
curl -s http://$ALB_URL/health | jq '{status, version, environment}'
echo ""
echo "ASG Status:"
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]' \
  --output text
echo ""
echo "RDS Status:"
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].[DBInstanceStatus,MultiAZ]' \
  --output text
echo ""
echo "Alarms in ALARM state:"
aws cloudwatch describe-alarms \
  --region $AWS_REGION \
  --alarm-name-prefix demo-app-prod \
  --state-value ALARM \
  --query 'MetricAlarms[].AlarmName' \
  --output text
echo ""
echo "✓ Production verification complete!"
```

## Что делать если что-то упало?

### Приложение не отвечает
1. Проверь target health: `aws elbv2 describe-target-health --target-group-arn $TG_ARN`
2. Проверь логи: `aws logs tail /aws/ec2/demo-app-prod-application --follow`
3. Проверь security groups
4. Instance refresh: `aws autoscaling start-instance-refresh --auto-scaling-group-name $ASG_NAME`

### Alarms в состоянии ALARM
1. Проверь причину: `aws cloudwatch describe-alarms --state-value ALARM`
2. Посмотри метрики в Dashboard
3. Проверь логи приложения

### Database connection failed
1. Проверь RDS status: `aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE`
2. Проверь security groups
3. Проверь secrets: `aws secretsmanager get-secret-value --secret-id demo-app-prod-db-creds`

### Email не приходит
1. Проверь subscription status
2. Проверь spam folder
3. Отправь test message через SNS
