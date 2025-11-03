#!/bin/bash
#####################################
# EC2 Instance User Data Script
#####################################
# This script runs on instance launch to:
# - Install required packages
# - Configure CloudWatch agent
# - Pull and run Docker container
# - Setup application
#####################################

set -e

# Redirect output to log files
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "======================================"
echo "Starting EC2 instance configuration"
echo "Environment: ${environment}"
echo "Region: ${region}"
echo "Application Port: ${application_port}"
echo "======================================"

#####################################
# Install required packages (skip system update to avoid conflicts)
#####################################
echo "Installing required packages..."
dnf install -y \
  docker \
  python3-pip \
  postgresql15 \
  jq \
  wget \
  git \
  amazon-cloudwatch-agent

#####################################
# Start Docker service
#####################################
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user

#####################################
# Install AWS CLI v2
#####################################
echo "Installing AWS CLI v2..."
if ! command -v aws &> /dev/null; then
  cd /tmp
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install
  rm -rf aws awscliv2.zip
fi

#####################################
# Configure CloudWatch Agent
#####################################
echo "Configuring CloudWatch agent..."
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

# Start CloudWatch agent
echo "Starting CloudWatch agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

#####################################
# Get instance metadata
#####################################
echo "Retrieving instance metadata..."
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

echo "Instance ID: $INSTANCE_ID"
echo "Instance IP: $INSTANCE_IP"
echo "Availability Zone: $AZ"

#####################################
# Retrieve database credentials
#####################################
# Using AWS RDS Managed Master Password approach:
# 1. Connection details secret contains host, port, username, and ARN to password secret
# 2. Password is stored separately in AWS-managed secret (never in Terraform state)
# 3. Application retrieves both secrets at runtime
#####################################
if [ -n "${db_secret_arn}" ]; then
  echo "Retrieving database connection details from Secrets Manager..."

  # Get connection details (host, port, username, etc.)
  DB_CONNECTION=$(aws secretsmanager get-secret-value \
    --secret-id ${db_secret_arn} \
    --region ${region} \
    --query SecretString \
    --output text)

  export DB_HOST=$(echo $DB_CONNECTION | jq -r '.host')
  export DB_PORT=$(echo $DB_CONNECTION | jq -r '.port')
  export DB_NAME=$(echo $DB_CONNECTION | jq -r '.dbname')
  export DB_USER=$(echo $DB_CONNECTION | jq -r '.username')

  # Get ARN of the AWS-managed password secret
  MASTER_SECRET_ARN=$(echo $DB_CONNECTION | jq -r '.masterUserSecretArn')

  # Retrieve the actual password from AWS-managed secret
  echo "Retrieving database password from AWS-managed secret..."
  DB_PASSWORD_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id $MASTER_SECRET_ARN \
    --region ${region} \
    --query SecretString \
    --output text)

  export DB_PASSWORD=$(echo $DB_PASSWORD_SECRET | jq -r '.password')

  echo "Database host: $DB_HOST"
  echo "Database port: $DB_PORT"
  echo "Database name: $DB_NAME"
  echo "Database user: $DB_USER"
  echo "Password retrieved from AWS-managed secret: ✓"
fi

#####################################
# ECR Login (if ECR repository provided)
#####################################
if [ -n "${ecr_repository_url}" ]; then
  echo "Logging in to ECR..."
  aws ecr get-login-password --region ${region} | \
    docker login --username AWS --password-stdin ${ecr_repository_url}
fi

#####################################
# Create application directory
#####################################
echo "Creating application directory..."
mkdir -p /opt/application
cd /opt/application

#####################################
# Create environment file
#####################################
echo "Creating environment file..."
cat > /opt/application/.env <<EOF
# Application Configuration
ENVIRONMENT=${environment}
APPLICATION_PORT=${application_port}
AWS_REGION=${region}
INSTANCE_ID=$INSTANCE_ID
INSTANCE_IP=$INSTANCE_IP
AVAILABILITY_ZONE=$AZ

# Database Configuration (if available)
DB_HOST=$${DB_HOST:-}
DB_PORT=$${DB_PORT:-5432}
DB_NAME=$${DB_NAME:-appdb}
DB_USER=$${DB_USER:-}
DB_PASSWORD=$${DB_PASSWORD:-}

# Application Version
APP_VERSION=${app_version}

# Log Configuration
LOG_LEVEL=INFO
LOG_FORMAT=json
EOF

#####################################
# Pull and run Docker container (if ECR URL provided)
#####################################
if [ -n "${ecr_repository_url}" ]; then
  echo "Pulling Docker image from ECR..."
  docker pull ${ecr_repository_url}:${app_version}

  echo "Running Docker container..."
  docker run -d \
    --name application \
    --restart unless-stopped \
    -p ${application_port}:${application_port} \
    --env-file /opt/application/.env \
    -v /var/log:/var/log \
    ${ecr_repository_url}:${app_version}

  echo "Docker container started successfully"
else
  #####################################
  # Alternative: Install application directly
  #####################################
  echo "Installing Flask application directly..."

  # Create virtual environment
  python3 -m venv /opt/application/venv
  source /opt/application/venv/bin/activate

  # Install dependencies
  pip install --upgrade pip
  pip install flask gunicorn psycopg2-binary boto3 requests

  # Create simple Flask app
  cat > /opt/application/app.py <<'PYEOF'
import os
import socket
import json
import psycopg2
from flask import Flask, jsonify, request
from datetime import datetime

app = Flask(__name__)

def get_db_connection():
    """Create database connection"""
    try:
        conn = psycopg2.connect(
            host=os.getenv('DB_HOST'),
            port=os.getenv('DB_PORT'),
            database=os.getenv('DB_NAME'),
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASSWORD')
        )
        return conn
    except Exception as e:
        print(f"Database connection error: {e}")
        return None

@app.route('/')
def index():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'hostname': socket.gethostname(),
        'instance_id': os.getenv('INSTANCE_ID'),
        'instance_ip': os.getenv('INSTANCE_IP'),
        'availability_zone': os.getenv('AVAILABILITY_ZONE'),
        'environment': os.getenv('ENVIRONMENT'),
        'version': os.getenv('APP_VERSION'),
        'timestamp': datetime.utcnow().isoformat()
    })

@app.route('/health')
def health():
    """Detailed health check"""
    health_status = {
        'status': 'healthy',
        'checks': {
            'application': 'ok',
            'database': 'unknown'
        }
    }

    # Check database connection
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute('SELECT 1')
            cursor.close()
            conn.close()
            health_status['checks']['database'] = 'ok'
        else:
            health_status['checks']['database'] = 'error'
            health_status['status'] = 'degraded'
    except Exception as e:
        health_status['checks']['database'] = f'error: {str(e)}'
        health_status['status'] = 'degraded'

    status_code = 200 if health_status['status'] == 'healthy' else 503
    return jsonify(health_status), status_code

@app.route('/db')
def db_check():
    """Database connectivity check"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute('SELECT version()')
            db_version = cursor.fetchone()[0]
            cursor.close()
            conn.close()

            return jsonify({
                'status': 'connected',
                'database_version': db_version,
                'host': os.getenv('DB_HOST'),
                'database': os.getenv('DB_NAME')
            })
        else:
            return jsonify({
                'status': 'error',
                'message': 'Could not connect to database'
            }), 503
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 503

@app.route('/metrics')
def metrics():
    """Prometheus-style metrics"""
    metrics_data = []
    metrics_data.append(f'application_up 1')
    metrics_data.append(f'application_info{{version="{os.getenv("APP_VERSION")}",environment="{os.getenv("ENVIRONMENT")}"}} 1')

    return '\n'.join(metrics_data), 200, {'Content-Type': 'text/plain'}

if __name__ == '__main__':
    port = int(os.getenv('APPLICATION_PORT', 5001))
    app.run(host='0.0.0.0', port=port)
PYEOF

  # Create systemd service
  cat > /etc/systemd/system/application.service <<'SVCEOF'
[Unit]
Description=Flask Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/application
Environment="PATH=/opt/application/venv/bin"
EnvironmentFile=/opt/application/.env
ExecStart=/opt/application/venv/bin/gunicorn \
  --bind 0.0.0.0:${application_port} \
  --workers 4 \
  --timeout 120 \
  --access-logfile /var/log/application.log \
  --error-logfile /var/log/application.log \
  app:app
Restart=always

[Install]
WantedBy=multi-user.target
SVCEOF

  # Fix permissions
  chown -R ec2-user:ec2-user /opt/application

  # Start application service
  systemctl daemon-reload
  systemctl enable application
  systemctl start application

  echo "Flask application started successfully"
fi

#####################################
# Custom user data (if provided)
#####################################
${custom_user_data}

#####################################
# Wait for application to be healthy
#####################################
echo "Waiting for application to be healthy..."
for i in {1..30}; do
  if curl -f http://localhost:${application_port}/health > /dev/null 2>&1; then
    echo "Application is healthy!"
    break
  fi
  echo "Waiting for application to start... ($i/30)"
  sleep 10
done

#####################################
# Completion
#####################################
echo "======================================"
echo "EC2 instance configuration completed!"
echo "Application is running on port ${application_port}"
echo "======================================"

# Signal completion to CloudFormation (if used)
# /opt/aws/bin/cfn-signal -e $? --stack STACK_NAME --resource AutoScalingGroup --region ${region}
