#####################################
# VPC Module - Main Configuration
#####################################
# Creates a highly available VPC with:
# - Multiple Availability Zones (default: 3)
# - Public subnets for ALB and NAT Gateways
# - Private subnets for application tier
# - Database subnets (isolated from internet)
# - Internet Gateway for public internet access
# - NAT Gateways for private subnet outbound traffic
# - VPC Flow Logs for network monitoring
#####################################

locals {
  # Calculate the number of AZs to use based on available AZs and requested count
  az_count = min(var.azs_count, length(data.aws_availability_zones.available.names))

  # Common tags for all resources
  common_tags = merge(
    var.tags,
    {
      Module      = "vpc"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  )
}

#####################################
# Data Sources
#####################################

# Get available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

#####################################
# VPC
#####################################

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Enable DNS support for RDS and other services
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Enable Network Address Usage Metrics
  enable_network_address_usage_metrics = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-vpc"
    }
  )
}

#####################################
# Internet Gateway
#####################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-igw"
    }
  )

  # Ensure proper cleanup order during destroy
  lifecycle {
    create_before_destroy = false
  }
}

#####################################
# Public Subnets
#####################################
# Used for: ALB, NAT Gateways, Bastion (optional)

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Auto-assign public IPs for resources in public subnets
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-public-${data.aws_availability_zones.available.names[count.index]}"
      Tier = "Public"
      Type = "public"
    }
  )
}

#####################################
# Private Subnets (Application Tier)
#####################################
# Used for: EC2 instances, ECS tasks, Lambda (in VPC)

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # Private subnets should not auto-assign public IPs
  map_public_ip_on_launch = false

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-private-${data.aws_availability_zones.available.names[count.index]}"
      Tier = "Private"
      Type = "private"
    }
  )
}

#####################################
# Database Subnets (Isolated Tier)
#####################################
# Used for: RDS, ElastiCache, Redshift
# No direct route to Internet Gateway or NAT Gateway

resource "aws_subnet" "database" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = false

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-database-${data.aws_availability_zones.available.names[count.index]}"
      Tier = "Database"
      Type = "database"
    }
  )
}

#####################################
# Elastic IPs for NAT Gateways
#####################################

resource "aws_eip" "nat" {
  count = var.single_nat_gateway ? 1 : local.az_count

  domain = "vpc"

  # Ensure VPC is created before EIP
  depends_on = [aws_internet_gateway.main]

  tags = merge(
    local.common_tags,
    {
      Name = var.single_nat_gateway ? "${var.name_prefix}-nat-eip" : "${var.name_prefix}-nat-eip-${data.aws_availability_zones.available.names[count.index]}"
    }
  )
}

#####################################
# NAT Gateways
#####################################
# Provides outbound internet access for private subnets
# HA: One NAT Gateway per AZ (or single for cost optimization)

resource "aws_nat_gateway" "main" {
  count = var.single_nat_gateway ? 1 : local.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    local.common_tags,
    {
      Name = var.single_nat_gateway ? "${var.name_prefix}-nat" : "${var.name_prefix}-nat-${data.aws_availability_zones.available.names[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

#####################################
# Route Tables
#####################################

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-public-rt"
      Type = "public"
    }
  )
}

# Public Route to Internet Gateway
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id

  # Ensure route is created after IGW and destroyed before IGW
  depends_on = [aws_internet_gateway.main]
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables (one per AZ for HA, or shared if single NAT)
resource "aws_route_table" "private" {
  count = var.single_nat_gateway ? 1 : local.az_count

  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = var.single_nat_gateway ? "${var.name_prefix}-private-rt" : "${var.name_prefix}-private-rt-${data.aws_availability_zones.available.names[count.index]}"
      Type = "private"
    }
  )
}

# Private Route to NAT Gateway
resource "aws_route" "private_nat" {
  count = var.single_nat_gateway ? 1 : local.az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

# Associate private subnets with private route tables
resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index].id
}

# Database Route Table (isolated, no internet access)
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-database-rt"
      Type = "database"
    }
  )
}

# Associate database subnets with database route table
resource "aws_route_table_association" "database" {
  count = local.az_count

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

#####################################
# VPC Flow Logs
#####################################
# Captures network traffic for security and troubleshooting

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name_prefix}-flow-logs"
  retention_in_days = var.flow_logs_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-vpc-flow-logs"
    }
  )
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name_prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name_prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.vpc_flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type    = var.flow_logs_traffic_type
  vpc_id          = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-vpc-flow-log"
    }
  )
}

#####################################
# VPC Endpoints (Optional)
#####################################
# Provides private connectivity to AWS services without NAT Gateway

# S3 Gateway Endpoint (no additional cost)
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.database.id]
  )

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-s3-endpoint"
    }
  )
}

# DynamoDB Gateway Endpoint (no additional cost)
resource "aws_vpc_endpoint" "dynamodb" {
  count = var.enable_dynamodb_endpoint ? 1 : 0

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.dynamodb"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-dynamodb-endpoint"
    }
  )
}

#####################################
# Default Network ACL (Optional)
#####################################
# Add custom rules to default NACL for additional security layer

resource "aws_default_network_acl" "default" {
  count = var.manage_default_network_acl ? 1 : 0

  default_network_acl_id = aws_vpc.main.default_network_acl_id

  # Allow all inbound traffic by default
  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # Allow all outbound traffic by default
  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-default-nacl"
    }
  )
}

#####################################
# DHCP Options Set (Optional)
#####################################

resource "aws_vpc_dhcp_options" "main" {
  count = var.enable_dhcp_options ? 1 : 0

  domain_name         = var.dhcp_options_domain_name != "" ? var.dhcp_options_domain_name : "${var.aws_region}.compute.internal"
  domain_name_servers = var.dhcp_options_domain_name_servers

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-dhcp-options"
    }
  )
}

resource "aws_vpc_dhcp_options_association" "main" {
  count = var.enable_dhcp_options ? 1 : 0

  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.main[0].id
}
