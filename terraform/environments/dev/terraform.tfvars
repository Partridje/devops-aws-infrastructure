#####################################
# Development Environment Configuration
#####################################

# Project configuration
project_name = "demo-app"
environment  = "dev"
aws_region   = "eu-north-1"

# Network configuration
vpc_cidr = "10.0.0.0/16"

# Application configuration
application_port = 5001

# Database configuration
database_name = "appdb"
rds_port      = 5432

#####################################
# Monitoring Configuration
#####################################
# Email addresses configured via environment variable or left empty for dev
# alert_email_addresses = []  # Uncomment and add emails if needed for dev alerts
