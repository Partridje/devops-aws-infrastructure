#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1
echo "Starting EC2 instance configuration"
dnf install -y \
  docker \
  python3-pip \
  postgresql15 \
  jq \
  wget \
  git \
  amazon-cloudwatch-agent
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user
if ! command -v aws &> /dev/null; then
  cd /tmp
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install
  rm -rf aws awscliv2.zip
fi
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/application.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/application",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/user-data",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/docker.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/docker",
            "retention_in_days": 7
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Application/${environment}",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "rename": "CPU_IDLE",
            "unit": "Percent"
          },
          {
            "name": "cpu_usage_iowait",
            "rename": "CPU_IOWAIT",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60,
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DISK_USED",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "diskio": {
        "measurement": [
          {
            "name": "io_time"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MEMORY_USED",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          {
            "name": "tcp_established",
            "rename": "TCP_ESTABLISHED",
            "unit": "Count"
          },
          {
            "name": "tcp_time_wait",
            "rename": "TCP_TIME_WAIT",
            "unit": "Count"
          }
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
if [ -n "${db_secret_arn}" ]; then
  DB_CONNECTION=$(aws secretsmanager get-secret-value \
    --secret-id ${db_secret_arn} \
    --region ${region} \
    --query SecretString \
    --output text)

  export DB_HOST=$(echo $DB_CONNECTION | jq -r '.host')
  export DB_PORT=$(echo $DB_CONNECTION | jq -r '.port')
  export DB_NAME=$(echo $DB_CONNECTION | jq -r '.dbname')
  export DB_USER=$(echo $DB_CONNECTION | jq -r '.username')
  MASTER_SECRET_ARN=$(echo $DB_CONNECTION | jq -r '.masterUserSecretArn')
  DB_PASSWORD_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id $MASTER_SECRET_ARN \
    --region ${region} \
    --query SecretString \
    --output text)

  export DB_PASSWORD=$(echo $DB_PASSWORD_SECRET | jq -r '.password')
fi
if [ -n "${ecr_repository_url}" ]; then
  aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${ecr_repository_url}
fi
mkdir -p /opt/application
cd /opt/application
cat > /opt/application/.env <<EOF
# Application Configuration
ENVIRONMENT=${environment}
APPLICATION_PORT=${application_port}
AWS_REGION=${region}
INSTANCE_ID=$INSTANCE_ID
INSTANCE_IP=$INSTANCE_IP
AVAILABILITY_ZONE=$AZ

# Log Configuration
LOG_LEVEL=INFO
LOG_FORMAT=json
EOF

if [ -n "$${DB_HOST:-}" ]; then
  {
    echo ""
    echo "# Database Configuration"
    printf 'DB_HOST=%s\n' "$${DB_HOST}"
    printf 'DB_PORT=%s\n' "$${DB_PORT:-5432}"
    printf 'DB_NAME=%s\n' "$${DB_NAME:-appdb}"
    printf 'DB_USER=%s\n' "$${DB_USER}"
    printf 'DB_PASSWORD=%s\n' "$${DB_PASSWORD}"
  } >> /opt/application/.env
fi
if [ -n "${ecr_repository_url}" ]; then
  cat > /usr/local/bin/deploy-app.sh <<'DEPLOY_SCRIPT'
#!/bin/bash
set -e
# Read only safe variables from .env (grep -v to exclude DB_PASSWORD)
AWS_REGION=$(grep '^AWS_REGION=' /opt/application/.env | cut -d'=' -f2)
SSM_PARAM=$(grep '^SSM_PARAMETER_NAME=' /opt/application/.env | cut -d'=' -f2)
ECR_REPO="${ecr_repository_url}"
APP_PORT="${application_port}"
APP_VERSION=$(aws ssm get-parameter --name "$SSM_PARAM" --region "$AWS_REGION" --query 'Parameter.Value' --output text 2>/dev/null)
if [ -z "$APP_VERSION" ] || [ "$APP_VERSION" == "initial" ]; then
  exit 0
fi
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPO" >/dev/null 2>&1
if docker ps -a --format '{{.Names}}' | grep -q '^application$'; then
  docker stop application >/dev/null 2>&1 || true
  docker rm application >/dev/null 2>&1 || true
fi
docker pull "$ECR_REPO:$APP_VERSION"
docker run -d \
  --name application \
  --restart unless-stopped \
  -p "$APP_PORT:$APP_PORT" \
  --env-file /opt/application/.env \
  -v /var/log:/var/log \
  "$ECR_REPO:$APP_VERSION"
DEPLOY_SCRIPT

  chmod +x /usr/local/bin/deploy-app.sh
  printf 'SSM_PARAMETER_NAME=%s\n' "${ssm_parameter_name}" >> /opt/application/.env
  cat > /etc/systemd/system/app-launcher.service <<'SYSTEMD_SERVICE'
[Unit]
Description=Application Launcher Service
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=/opt/application/.env
ExecStart=/usr/local/bin/deploy-app.sh
ExecStop=/usr/bin/docker stop application
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE

  systemctl daemon-reload
  systemctl enable app-launcher.service
  systemctl start app-launcher.service || true
fi
${custom_user_data}
for i in {1..30}; do
  curl -f http://localhost:${application_port}/health > /dev/null 2>&1 && break
  sleep 10
done
echo "EC2 instance configuration completed"
