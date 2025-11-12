#####################################
# EC2 Module - Main Configuration
#####################################
# Creates a highly available application tier with:
# - Application Load Balancer (ALB)
# - Auto Scaling Group (ASG)
# - Launch Template with user data
# - Target Group with health checks
# - Scaling policies
# - IAM instance profile
# - CloudWatch log group
#####################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "ec2"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  )

  # Generate names
  alb_name          = "${var.name_prefix}-alb"
  target_group_name = "${var.name_prefix}-tg"
  asg_name          = "${var.name_prefix}-asg"
}

#####################################
# Data Sources
#####################################

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

#####################################
# CloudWatch Log Group
#####################################
# For application logs

resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/ec2/${var.name_prefix}-application"
  retention_in_days = var.log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-application-logs"
    }
  )
}

#####################################
# IAM Role for EC2 Instances
#####################################

resource "aws_iam_role" "ec2_role" {
  name_prefix = "${var.name_prefix}-ec2-role-"
  description = "IAM role for EC2 instances in ${var.name_prefix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Policy for CloudWatch Logs
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name_prefix = "${var.name_prefix}-cloudwatch-logs-"
  role        = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.application.arn}:*"
      }
    ]
  })
}

# Policy for Secrets Manager (to read RDS credentials)
resource "aws_iam_role_policy" "secrets_manager" {
  name_prefix = "${var.name_prefix}-secrets-manager-"
  role        = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = compact([
          var.db_secret_arn != "" ? var.db_secret_arn : "",
          var.db_master_secret_arn != "" ? var.db_master_secret_arn : ""
        ])
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.rds_kms_key_arn != "" ? var.rds_kms_key_arn : "*"
      }
    ]
  })
}

# Policy for ECR (to pull Docker images)
resource "aws_iam_role_policy" "ecr" {
  count = var.enable_ecr_access ? 1 : 0

  name_prefix = "${var.name_prefix}-ecr-"
  role        = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for SSM Parameter Store (to read app version)
resource "aws_iam_role_policy" "ssm_parameter" {
  name_prefix = "${var.name_prefix}-ssm-parameter-"
  role        = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = var.ssm_parameter_arn
      }
    ]
  })
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "${var.name_prefix}-ec2-profile-"
  role        = aws_iam_role.ec2_role.name

  tags = local.common_tags
}

#####################################
# Application Load Balancer
#####################################

resource "aws_lb" "main" {
  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.alb_security_group_ids
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  enable_waf_fail_open             = false
  drop_invalid_header_fields       = true

  idle_timeout = var.alb_idle_timeout

  access_logs {
    enabled = var.enable_alb_access_logs
    bucket  = var.alb_access_logs_bucket
    prefix  = var.alb_access_logs_prefix
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.alb_name
    }
  )
}

#####################################
# Target Group
#####################################

resource "aws_lb_target_group" "main" {
  name_prefix = substr(var.name_prefix, 0, 6)
  port        = var.application_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  target_type = "instance"

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    protocol            = "HTTP"
  }

  # Deregistration delay (connection draining)
  deregistration_delay = var.deregistration_delay

  # Stickiness
  stickiness {
    enabled         = var.enable_stickiness
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.target_group_name
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#####################################
# ALB Listeners
#####################################

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action: forward to target group or redirect to HTTPS
  default_action {
    type = var.enable_https_redirect ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.enable_https_redirect ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    target_group_arn = var.enable_https_redirect ? null : aws_lb_target_group.main.arn
  }

  tags = local.common_tags
}

# HTTPS Listener (optional)
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = local.common_tags
}

#####################################
# Launch Template
#####################################

resource "aws_launch_template" "main" {
  name_prefix   = "${var.name_prefix}-lt-"
  description   = "Launch template for ${var.name_prefix} application"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  # IMDSv2 enforcement for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Monitoring
  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  # Network interface configuration
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = var.application_security_group_ids
  }

  # IAM instance profile
  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_profile.arn
  }

  # EBS volume configuration
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      encrypted             = true
      delete_on_termination = true
      iops                  = var.root_volume_type == "io1" || var.root_volume_type == "io2" ? var.root_volume_iops : null
    }
  }

  # User data script
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    region             = data.aws_region.current.id
    aws_region         = data.aws_region.current.id
    log_group_name     = aws_cloudwatch_log_group.application.name
    application_port   = var.application_port
    db_secret_arn      = var.db_secret_arn
    environment        = var.environment
    ssm_parameter_name = var.ssm_parameter_name
    ecr_repository_url = var.ecr_repository_url
    custom_user_data   = var.custom_user_data
  }))

  # Tags to propagate to instances
  tag_specifications {
    resource_type = "instance"

    tags = merge(
      local.common_tags,
      {
        Name = "${var.name_prefix}-instance"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(
      local.common_tags,
      {
        Name = "${var.name_prefix}-volume"
      }
    )
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-launch-template"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#####################################
# Auto Scaling Group
#####################################

resource "aws_autoscaling_group" "main" {
  name_prefix = "${var.name_prefix}-asg-"

  # Capacity configuration
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  # Health checks
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  # Network configuration
  vpc_zone_identifier = var.private_subnet_ids

  # Launch template
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Default"
  }

  # Target group attachment
  target_group_arns = [aws_lb_target_group.main.arn]

  # Instance refresh (for rolling updates)
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
      instance_warmup        = var.health_check_grace_period
    }
  }

  # Termination policies
  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  # Metrics to collect
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]

  # Wait for capacity timeout
  wait_for_capacity_timeout = "10m"

  # Protect from scale in (if needed)
  protect_from_scale_in = false

  dynamic "tag" {
    for_each = merge(
      local.common_tags,
      {
        Name = "${var.name_prefix}-asg-instance"
      }
    )

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      desired_capacity,
      target_group_arns,
      launch_template[0].version
    ]
  }

  depends_on = [
    aws_lb_target_group.main
  ]
}

#####################################
# Auto Scaling Policies
#####################################

# Target tracking - CPU utilization
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  count = var.enable_cpu_scaling ? 1 : 0

  name                   = "${var.name_prefix}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}

# Target tracking - ALB request count
resource "aws_autoscaling_policy" "alb_target_tracking" {
  count = var.enable_alb_scaling ? 1 : 0

  name                   = "${var.name_prefix}-alb-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.main.arn_suffix}"
    }
    target_value = var.alb_requests_per_target
  }
}

# Simple scaling - scale up
resource "aws_autoscaling_policy" "scale_up" {
  count = var.enable_simple_scaling ? 1 : 0

  name                   = "${var.name_prefix}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

# Simple scaling - scale down
resource "aws_autoscaling_policy" "scale_down" {
  count = var.enable_simple_scaling ? 1 : 0

  name                   = "${var.name_prefix}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.main.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

#####################################
# CloudWatch Alarms for Simple Scaling
#####################################

# Alarm to trigger scale up
resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  count = var.enable_simple_scaling ? 1 : 0

  alarm_name          = "${var.name_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = local.common_tags
}

# Alarm to trigger scale down
resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  count = var.enable_simple_scaling ? 1 : 0

  alarm_name          = "${var.name_prefix}-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = local.common_tags
}

#####################################
# CloudWatch Alarms for Monitoring
#####################################

# Unhealthy host count alarm
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count = var.create_monitoring_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Alert when there are unhealthy targets"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.main.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}

# High response time alarm
resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  count = var.create_monitoring_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 1.0
  alarm_description   = "Alert when target response time is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.main.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}

# HTTP 5xx errors alarm
resource "aws_cloudwatch_metric_alarm" "http_5xx_errors" {
  count = var.create_monitoring_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-http-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alert when there are too many 5xx errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.main.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = local.common_tags
}
