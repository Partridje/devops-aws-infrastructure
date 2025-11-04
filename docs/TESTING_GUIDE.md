# Testing Guide - Infrastructure and Auto Scaling

Руководство по тестированию production инфраструктуры, Auto Scaling, мониторинга и отказоустойчивости.

## 1. Auto Scaling Testing

### 1.1 CPU-Based Scaling Test

**Цель**: Проверить что ASG масштабируется при высокой нагрузке CPU.

```bash
# Получить ID инстанса
INSTANCE_ID=$(aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Подключиться к инстансу через SSM
aws ssm start-session --target $INSTANCE_ID --region eu-north-1

# На инстансе запустить CPU stress test
sudo yum install -y stress
stress --cpu 4 --timeout 600s  # 10 минут нагрузки на 4 ядра

# В другом терминале мониторить scaling
watch -n 10 'aws autoscaling describe-auto-scaling-groups \
  --region eu-north-1 \
  --auto-scaling-group-names demo-app-prod-asg-* \
  --query "AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]" \
  --output text'
```

**Ожидаемый результат**:
- CPU метрика поднимется выше 70%
- Через 2-3 минуты desired capacity увеличится
- CloudWatch alarm `demo-app-prod-cpu-high` перейдет в ALARM
- Новый инстанс запустится
- После остановки stress CPU вернется к норме
- Desired capacity уменьшится обратно до минимума

### 1.2 Request-Based Scaling Test

**Цель**: Проверить масштабирование по количеству запросов.

```bash
# Получить ALB URL
ALB_URL=$(aws elbv2 describe-load-balancers \
  --region eu-north-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `prod`)].DNSName' \
  --output text)

# Запустить load test (требуется apache-bench)
sudo apt-get install -y apache2-utils  # на Linux
# или
brew install httpie wrk  # на macOS

# Генерировать нагрузку
wrk -t12 -c400 -d5m http://$ALB_URL/health
# или
ab -n 100000 -c 50 http://$ALB_URL/health

# Мониторить
watch -n 5 'echo "=== ALB Metrics ==="; \
aws cloudwatch get-metric-statistics \
  --region eu-north-1 \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=app/demo-app-prod-alb/* \
  --start-time $(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average'
```

**Ожидаемый результат**:
- RequestCountPerTarget > 1000
- ASG добавит инстансы
- Response time останется приемлемым
- WAF может блокировать если rate limit превышен

### 1.3 Manual Scaling Test

**Цель**: Проверить что можно вручную изменить capacity.

```bash
# Увеличить desired capacity до 4
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --region eu-north-1 \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `prod`)].AutoScalingGroupName' \
  --output text)

aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 4 \
  --region eu-north-1

# Проверить scaling activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name $ASG_NAME \
  --region eu-north-1 \
  --max-records 5

# Вернуть обратно
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 2 \
  --region eu-north-1
```

## 2. High Availability Testing

### 2.1 Multi-AZ Failover Test

**Цель**: Проверить что приложение работает при падении одной AZ.

```bash
# Посмотреть текущее распределение
aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone,PrivateIpAddress]' \
  --output table

# Терминировать все инстансы в одной AZ (симуляция отказа AZ)
INSTANCES_AZ_A=$(aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" \
       "Name=instance-state-name,Values=running" \
       "Name=availability-zone,Values=eu-north-1a" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

aws ec2 terminate-instances --instance-ids $INSTANCES_AZ_A --region eu-north-1

# Проверить что ALB перенаправляет трафик на оставшиеся AZ
for i in {1..20}; do
  curl -s http://$ALB_URL/health | jq '.instance.az'
  sleep 1
done

# ASG должен запустить новые инстансы в других AZ
watch -n 5 'aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running,pending" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,Placement.AvailabilityZone]" \
  --output table'
```

**Ожидаемый результат**:
- Приложение доступно без downtime
- ALB переключает трафик на здоровые targets
- ASG запускает замену в других AZ
- RDS Multi-AZ продолжает работать

### 2.2 RDS Failover Test

**Цель**: Проверить автоматический failover RDS.

```bash
# Принудительный failover (ВНИМАНИЕ: кратковременный downtime БД)
DB_INSTANCE=$(aws rds describe-db-instances \
  --region eu-north-1 \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `prod`)].DBInstanceIdentifier' \
  --output text)

echo "Инициирую failover для $DB_INSTANCE (будет ~2 минуты недоступности)"
read -p "Продолжить? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  aws rds reboot-db-instance \
    --db-instance-identifier $DB_INSTANCE \
    --force-failover-allowed \
    --region eu-north-1
fi

# Мониторить статус
watch -n 5 'aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region eu-north-1 \
  --query "DBInstances[0].[DBInstanceStatus,AvailabilityZone]" \
  --output text'

# Проверить что приложение переподключается
for i in {1..60}; do
  STATUS=$(curl -s http://$ALB_URL/db | jq -r '.status')
  echo "$(date +%H:%M:%S) - DB Status: $STATUS"
  sleep 2
done
```

**Ожидаемый результат**:
- RDS failover займет 1-2 минуты
- Приложение покажет временные ошибки подключения
- Приложение автоматически переподключится
- Endpoint остается тем же (AWS DNS обновляется)

## 3. Instance Refresh Testing

### 3.1 Rolling Update Test

**Цель**: Обновить все инстансы без downtime.

```bash
# Запустить instance refresh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name $ASG_NAME \
  --region eu-north-1 \
  --preferences '{
    "MinHealthyPercentage": 100,
    "InstanceWarmup": 120
  }'

# Получить refresh ID
REFRESH_ID=$(aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name $ASG_NAME \
  --region eu-north-1 \
  --query 'InstanceRefreshes[0].InstanceRefreshId' \
  --output text)

# Мониторить прогресс
watch -n 10 'aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name $ASG_NAME \
  --region eu-north-1 \
  --instance-refresh-ids $REFRESH_ID \
  --query "InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]" \
  --output table'

# В параллельном окне - проверять доступность
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" http://$ALB_URL/health
  sleep 2
done
```

**Ожидаемый результат**:
- MinHealthyPercentage: 100 = zero downtime
- Инстансы обновляются по одному
- ALB всегда имеет healthy targets
- Все HTTP запросы возвращают 200

## 4. WAF Testing

### 4.1 Rate Limiting Test

**Цель**: Проверить что WAF блокирует превышение rate limit.

```bash
# Быстро отправить много запросов с одного IP
for i in {1..3000}; do
  curl -s http://$ALB_URL/ > /dev/null &
done

# Проверить что получаем 403
curl -v http://$ALB_URL/

# Посмотреть WAF метрики
aws cloudwatch get-metric-statistics \
  --region eu-north-1 \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --dimensions Name=WebACL,Value=demo-app-prod-web-acl \
              Name=Region,Value=eu-north-1 \
              Name=Rule,Value=RateLimitRule \
  --start-time $(date -u -d "10 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Ожидаемый результат**:
- После ~2000 запросов получаем 403 Forbidden
- WAF alarm `demo-app-prod-waf-rate-limit` активируется
- Блокировка снимается через 5 минут

### 4.2 SQL Injection Test (ДОЛЖЕН БЛОКИРОВАТЬСЯ)

**Цель**: Проверить что WAF блокирует SQL injection.

```bash
# Тест SQL injection (безопасно - только GET запрос)
curl -v "http://$ALB_URL/api/items?id=1' OR '1'='1"

# Должен вернуть 403 Forbidden
```

## 5. Monitoring & Alerts Testing

### 5.1 CloudWatch Alarms Test

**Цель**: Проверить что alarms работают и отправляют уведомления.

```bash
# Посмотреть все алармы
aws cloudwatch describe-alarms \
  --region eu-north-1 \
  --alarm-name-prefix demo-app-prod \
  --query 'MetricAlarms[].[AlarmName,StateValue]' \
  --output table

# Принудительно вызвать alarm (high CPU)
# ... используй stress test из раздела 1.1 ...

# Проверить историю alarm
aws cloudwatch describe-alarm-history \
  --region eu-north-1 \
  --alarm-name demo-app-prod-cpu-high \
  --history-item-type StateUpdate \
  --max-records 5
```

**Ожидаемый результат**:
- Alarm переходит в ALARM state
- SNS topic получает сообщение
- Email приходит на tcytcerov@gmail.com

### 5.2 Application Logs Test

**Цель**: Проверить что логи собираются в CloudWatch.

```bash
# Посмотреть последние логи
aws logs tail /aws/ec2/demo-app-prod-application \
  --region eu-north-1 \
  --follow

# Сгенерировать тестовые запросы
for i in {1..50}; do
  curl -s http://$ALB_URL/ > /dev/null
  curl -s http://$ALB_URL/api/items > /dev/null
done

# Поиск ERROR в логах
aws logs filter-log-events \
  --region eu-north-1 \
  --log-group-name /aws/ec2/demo-app-prod-application \
  --filter-pattern "ERROR" \
  --max-items 10
```

## 6. Disaster Recovery Testing

### 6.1 Complete Infrastructure Recovery

**Цель**: Проверить восстановление из полного отказа.

```bash
# 1. Сделать snapshot текущего состояния
terraform -chdir=terraform/environments/prod show -json > backup-state.json

# 2. Уничтожить инфраструктуру (НЕ в production!!!)
# terraform -chdir=terraform/environments/prod destroy -auto-approve

# 3. Восстановить
# terraform -chdir=terraform/environments/prod apply -auto-approve

# 4. Проверить что всё работает
make smoke-test ENV=prod
```

### 6.2 RDS Snapshot Restore

**Цель**: Проверить восстановление БД из snapshot.

```bash
# Создать snapshot вручную
aws rds create-db-snapshot \
  --db-instance-identifier $DB_INSTANCE \
  --db-snapshot-identifier demo-app-prod-manual-snapshot-$(date +%Y%m%d) \
  --region eu-north-1

# Посмотреть snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier $DB_INSTANCE \
  --region eu-north-1 \
  --query 'DBSnapshots[].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table
```

## 7. Security Testing

### 7.1 Network Isolation Test

**Цель**: Проверить что приватные ресурсы недоступны извне.

```bash
# RDS endpoint не должен быть доступен публично
DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region eu-north-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Должен timeout (RDS в private subnet)
timeout 5 nc -zv $DB_ENDPOINT 5432 || echo "✓ RDS недоступен публично (правильно)"

# Приложения доступны только через ALB
INSTANCE_IP=$(aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

# Должен timeout (EC2 в private subnet)
timeout 5 curl http://$INSTANCE_IP:5001 || echo "✓ EC2 недоступен публично (правильно)"
```

### 7.2 IAM Permissions Test

**Цель**: Проверить что инстансы имеют минимальные необходимые права.

```bash
# Подключиться к инстансу
aws ssm start-session --target $INSTANCE_ID --region eu-north-1

# На инстансе попробовать выполнить запрещенные действия
aws ec2 describe-instances  # Должно быть запрещено
aws s3 ls                    # Должно быть запрещено

# Разрешенные действия
aws secretsmanager get-secret-value --secret-id demo-app-prod-db-creds  # ✓
aws ecr get-login-password  # ✓
aws logs put-log-events     # ✓
```

## 8. Performance Testing

### 8.1 Database Performance

**Цель**: Проверить производительность БД.

```bash
# API endpoint для создания записей
for i in {1..1000}; do
  curl -X POST http://$ALB_URL/api/items \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"item-$i\",\"value\":$i}" &
done
wait

# Проверить RDS Performance Insights
echo "Открой: https://console.aws.amazon.com/rds/home?region=eu-north-1#performance-insights:resourceId=$DB_INSTANCE"

# Проверить connection pool
curl -s http://$ALB_URL/db | jq
```

### 8.2 Latency Test

**Цель**: Измерить задержки на разных этапах.

```bash
# ALB latency
curl -w "@curl-format.txt" -o /dev/null -s http://$ALB_URL/health

# Создать curl-format.txt:
cat > curl-format.txt << 'EOF'
    time_namelookup:  %{time_namelookup}s\n
       time_connect:  %{time_connect}s\n
    time_appconnect:  %{time_appconnect}s\n
   time_pretransfer:  %{time_pretransfer}s\n
      time_redirect:  %{time_redirect}s\n
 time_starttransfer:  %{time_starttransfer}s\n
                    ----------\n
         time_total:  %{time_total}s\n
EOF

# CloudWatch ALB metrics
aws cloudwatch get-metric-statistics \
  --region eu-north-1 \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=app/demo-app-prod-alb/* \
  --start-time $(date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  --query 'Datapoints[*].[Timestamp,Average,Maximum]' \
  --output table
```

## Checklist тестирования перед production release

- [ ] Auto Scaling при CPU нагрузке работает
- [ ] Auto Scaling при request нагрузке работает
- [ ] Multi-AZ failover без downtime
- [ ] RDS failover проходит успешно
- [ ] Instance refresh без downtime
- [ ] WAF блокирует rate limit
- [ ] WAF блокирует SQL injection
- [ ] CloudWatch alarms активируются
- [ ] Email уведомления приходят
- [ ] Логи пишутся в CloudWatch
- [ ] RDS snapshots создаются автоматически
- [ ] Приватные ресурсы недоступны извне
- [ ] IAM permissions минимальны
- [ ] Performance приемлемый (< 200ms)
- [ ] Health checks проходят

## Автоматизация тестов

Можно создать скрипты для автоматизации:

```bash
# scripts/run-infrastructure-tests.sh
#!/bin/bash
set -e

ENV=${1:-prod}
REGION=${2:-eu-north-1}

echo "Running infrastructure tests for $ENV in $REGION..."

# 1. Health checks
echo "1. Health checks..."
make health-check ENV=$ENV

# 2. Smoke tests
echo "2. Smoke tests..."
make smoke-test ENV=$ENV

# 3. Check alarms
echo "3. Checking CloudWatch alarms..."
aws cloudwatch describe-alarms \
  --region $REGION \
  --alarm-name-prefix demo-app-$ENV \
  --state-value ALARM \
  --query 'MetricAlarms[].AlarmName'

# 4. Check target health
echo "4. Checking target health..."
TG_ARN=$(aws elbv2 describe-target-groups \
  --region $REGION \
  --query "TargetGroups[?contains(TargetGroupName, '$ENV')].TargetGroupArn" \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --region $REGION \
  --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`]'

echo "✅ All tests passed!"
```
