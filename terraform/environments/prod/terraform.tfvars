#####################################
# Production Environment Configuration
#####################################

# Project configuration
project_name = "demo-app"
environment  = "prod"
aws_region   = "eu-north-1"

# Network configuration
vpc_cidr = "10.1.0.0/16"

# Application configuration
application_port = 5001

# ECR repository
ecr_repository_url = "851725636341.dkr.ecr.eu-north-1.amazonaws.com/demo-flask-app"

#####################################
# HTTPS/SSL Configuration
#####################################
certificate_arn       = ""
enable_https_redirect = false
ssl_policy            = "ELBSecurityPolicy-TLS-1-2-2017-01"

# Database configuration
database_name = "appdb"
rds_port      = 5432

#####################################
# Monitoring Configuration
#####################################
# Email addresses configured via GitHub Secret: TF_VAR_alert_email_addresses
# alert_email_addresses = []  # Commented out - using GitHub Secret instead

#####################################
# WAF Configuration
#####################################
# Using defaults
