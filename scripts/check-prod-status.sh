#!/bin/bash
# Production Infrastructure Status Check

AWS_REGION=${AWS_REGION:-eu-north-1}
ALB_URL=${ALB_URL:-demo-app-prod-alb-619878086.eu-north-1.elb.amazonaws.com}

echo "=== PRODUCTION INFRASTRUCTURE STATUS ==="
echo ""

# Application
echo "📱 Application:"
APP_STATUS=$(curl -s http://$ALB_URL/health)
echo "$APP_STATUS" | jq '{status, version, environment, instance: .instance.id, az: .instance.az}'
echo ""

# Auto Scaling
echo "🔄 Auto Scaling Group:"
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `prod`)].AutoScalingGroupName' \
  --output text)
ASG_STATUS=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region $AWS_REGION \
  --query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]' \
  --output text)
echo "  Desired: $(echo $ASG_STATUS | awk '{print $1}'), Min: $(echo $ASG_STATUS | awk '{print $2}'), Max: $(echo $ASG_STATUS | awk '{print $3}')"
echo ""

# RDS
echo "🗄️  RDS Database:"
DB_INSTANCE=$(aws rds describe-db-instances \
  --region $AWS_REGION \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `prod`)].DBInstanceIdentifier' \
  --output text)
DB_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].[DBInstanceStatus,MultiAZ,DBInstanceClass]' \
  --output text)
echo "  Status: $(echo $DB_STATUS | awk '{print $1}'), Multi-AZ: $(echo $DB_STATUS | awk '{print $2}'), Class: $(echo $DB_STATUS | awk '{print $3}')"
echo ""

# Alarms
echo "🚨 CloudWatch Alarms:"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
  --region $AWS_REGION \
  --alarm-name-prefix demo-app-prod \
  --state-value ALARM \
  --query 'length(MetricAlarms)' \
  --output text)
echo "  Alarms in ALARM state: $ALARM_COUNT"
echo ""

# SNS
echo "📧 SNS Subscriptions:"
SNS_STATUS=$(aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:$AWS_REGION:851725636341:demo-app-prod-prod-alarms \
  --region $AWS_REGION \
  --query 'Subscriptions[0].[Endpoint,SubscriptionArn]' \
  --output text)
EMAIL=$(echo "$SNS_STATUS" | awk '{print $1}')
SUB_ARN=$(echo "$SNS_STATUS" | awk '{print $2}')

echo "  Email: $EMAIL"
if [[ "$SUB_ARN" == *"PendingConfirmation"* ]]; then
  echo "  Status: ⚠️  Pending Confirmation"
else
  echo "  Status: ✓ Confirmed"
fi
echo ""

echo "✅ Production infrastructure check complete!"
