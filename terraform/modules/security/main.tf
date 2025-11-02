#####################################
# Security Module - Main Configuration
#####################################
# Creates security groups following least privilege principle:
# - ALB Security Group: Accepts HTTP/HTTPS from internet
# - Application Security Group: Accepts traffic only from ALB
# - RDS Security Group: Accepts traffic only from Application
# - Bastion Security Group: Optional, for SSH access
#####################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "security"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  )
}

#####################################
# ALB Security Group
#####################################
# Accepts inbound HTTP/HTTPS from internet
# Allows all outbound to application security group

resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-alb-sg"
      Tier = "Public"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Inbound HTTP from internet
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTP from internet"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  tags = {
    Name = "alb-http-ingress"
  }
}

# Inbound HTTPS from internet
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTPS from internet"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = {
    Name = "alb-https-ingress"
  }
}

# Outbound to application instances
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id

  description                  = "Allow traffic to application instances"
  referenced_security_group_id = aws_security_group.application.id
  from_port                    = var.application_port
  to_port                      = var.application_port
  ip_protocol                  = "tcp"

  tags = {
    Name = "alb-to-app-egress"
  }
}

# Outbound HTTPS for health checks and external API calls
resource "aws_vpc_security_group_egress_rule" "alb_https_egress" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTPS for health checks"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = {
    Name = "alb-https-egress"
  }
}

#####################################
# Application Security Group
#####################################
# Accepts traffic only from ALB
# Allows outbound to internet (via NAT), RDS, and AWS services

resource "aws_security_group" "application" {
  name_prefix = "${var.name_prefix}-app-"
  description = "Security group for application instances"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-app-sg"
      Tier = "Private"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Inbound from ALB
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.application.id

  description                  = "Allow traffic from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.application_port
  to_port                      = var.application_port
  ip_protocol                  = "tcp"

  tags = {
    Name = "app-from-alb-ingress"
  }
}

# Outbound HTTPS to internet (for package updates, AWS APIs)
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.application.id

  description = "Allow HTTPS to internet"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = {
    Name = "app-https-egress"
  }
}

# Outbound HTTP to internet (for package updates)
resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.application.id

  description = "Allow HTTP to internet"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  tags = {
    Name = "app-http-egress"
  }
}

# Outbound to RDS
resource "aws_vpc_security_group_egress_rule" "app_to_rds" {
  security_group_id = aws_security_group.application.id

  description                  = "Allow traffic to RDS"
  referenced_security_group_id = aws_security_group.rds.id
  from_port                    = var.rds_port
  to_port                      = var.rds_port
  ip_protocol                  = "tcp"

  tags = {
    Name = "app-to-rds-egress"
  }
}

# Outbound DNS (UDP and TCP)
resource "aws_vpc_security_group_egress_rule" "app_dns_udp" {
  security_group_id = aws_security_group.application.id

  description = "Allow DNS queries (UDP)"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 53
  to_port     = 53
  ip_protocol = "udp"

  tags = {
    Name = "app-dns-udp-egress"
  }
}

resource "aws_vpc_security_group_egress_rule" "app_dns_tcp" {
  security_group_id = aws_security_group.application.id

  description = "Allow DNS queries (TCP)"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 53
  to_port     = 53
  ip_protocol = "tcp"

  tags = {
    Name = "app-dns-tcp-egress"
  }
}

# Outbound NTP for time synchronization
resource "aws_vpc_security_group_egress_rule" "app_ntp" {
  security_group_id = aws_security_group.application.id

  description = "Allow NTP for time synchronization"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 123
  to_port     = 123
  ip_protocol = "udp"

  tags = {
    Name = "app-ntp-egress"
  }
}

#####################################
# RDS Security Group
#####################################
# Accepts traffic only from application security group
# No outbound rules needed (stateful firewall)

resource "aws_security_group" "rds" {
  name_prefix = "${var.name_prefix}-rds-"
  description = "Security group for RDS database"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-rds-sg"
      Tier = "Database"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Inbound from application
resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  security_group_id = aws_security_group.rds.id

  description                  = "Allow PostgreSQL from application"
  referenced_security_group_id = aws_security_group.application.id
  from_port                    = var.rds_port
  to_port                      = var.rds_port
  ip_protocol                  = "tcp"

  tags = {
    Name = "rds-from-app-ingress"
  }
}

# Optional: Inbound from bastion (if enabled)
resource "aws_vpc_security_group_ingress_rule" "rds_from_bastion" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.rds.id

  description                  = "Allow PostgreSQL from bastion"
  referenced_security_group_id = aws_security_group.bastion[0].id
  from_port                    = var.rds_port
  to_port                      = var.rds_port
  ip_protocol                  = "tcp"

  tags = {
    Name = "rds-from-bastion-ingress"
  }
}

#####################################
# Bastion Security Group (Optional)
#####################################
# For SSH access to private instances
# NOT RECOMMENDED: Use AWS Systems Manager Session Manager instead

resource "aws_security_group" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name_prefix = "${var.name_prefix}-bastion-"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-bastion-sg"
      Tier = "Public"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Inbound SSH from allowed CIDR blocks
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id

  description = "Allow SSH from allowed IPs"
  cidr_ipv4   = var.bastion_allowed_cidr
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"

  tags = {
    Name = "bastion-ssh-ingress"
  }
}

# Outbound SSH to private instances
resource "aws_vpc_security_group_egress_rule" "bastion_to_app" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id

  description                  = "Allow SSH to application instances"
  referenced_security_group_id = aws_security_group.application.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"

  tags = {
    Name = "bastion-to-app-egress"
  }
}

# Allow SSH from bastion to application (reverse rule)
resource "aws_vpc_security_group_ingress_rule" "app_from_bastion" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.application.id

  description                  = "Allow SSH from bastion"
  referenced_security_group_id = aws_security_group.bastion[0].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"

  tags = {
    Name = "app-from-bastion-ingress"
  }
}

#####################################
# VPC Endpoint Security Group
#####################################
# For interface VPC endpoints (SSM, ECR, etc.)

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoint_sg ? 1 : 0

  name_prefix = "${var.name_prefix}-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-vpc-endpoints-sg"
      Tier = "Private"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Inbound HTTPS from VPC
resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = var.enable_vpc_endpoint_sg ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id

  description = "Allow HTTPS from VPC"
  cidr_ipv4   = var.vpc_cidr
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  tags = {
    Name = "vpc-endpoints-https-ingress"
  }
}

#####################################
# Additional Custom Security Group
#####################################
# For additional services (Redis, ElastiCache, etc.)

resource "aws_security_group" "custom" {
  count = var.create_custom_sg ? 1 : 0

  name_prefix = "${var.name_prefix}-custom-"
  description = var.custom_sg_description
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-custom-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Dynamic ingress rules for custom security group
resource "aws_vpc_security_group_ingress_rule" "custom_ingress" {
  for_each = var.create_custom_sg ? var.custom_sg_ingress_rules : {}

  security_group_id = aws_security_group.custom[0].id

  description = each.value.description
  cidr_ipv4   = lookup(each.value, "cidr_ipv4", null)
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.ip_protocol

  tags = {
    Name = each.key
  }
}

# Dynamic egress rules for custom security group
resource "aws_vpc_security_group_egress_rule" "custom_egress" {
  for_each = var.create_custom_sg ? var.custom_sg_egress_rules : {}

  security_group_id = aws_security_group.custom[0].id

  description = each.value.description
  cidr_ipv4   = lookup(each.value, "cidr_ipv4", null)
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.ip_protocol

  tags = {
    Name = each.key
  }
}
