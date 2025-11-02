# Architecture Documentation

Comprehensive architecture documentation for the AWS infrastructure deployment.

## Table of Contents

- [Overview](#overview)
- [Architecture Diagram](#architecture-diagram)
- [Components](#components)
- [Network Design](#network-design)
- [Security Architecture](#security-architecture)
- [Data Flow](#data-flow)
- [High Availability](#high-availability)
- [Scalability](#scalability)
- [Disaster Recovery](#disaster-recovery)
- [Design Decisions](#design-decisions)

## Overview

This infrastructure implements a production-ready, highly available, and secure three-tier web application architecture on AWS using Infrastructure as Code (Terraform).

### Key Characteristics

- **Multi-AZ Deployment**: Resources distributed across 3 availability zones
- **Auto-Scaling**: Dynamic capacity adjustment based on load
- **High Availability**: No single point of failure
- **Security-First**: Defense in depth, least privilege access
- **Cost-Optimized**: Right-sized resources with scaling policies
- **Observable**: Comprehensive monitoring and logging
- **Infrastructure as Code**: 100% Terraform, version controlled

### Technology Stack

| Layer | Technology |
|-------|-----------|
| Compute | EC2 Auto Scaling Groups |
| Load Balancing | Application Load Balancer (ALB) |
| Database | PostgreSQL on RDS Multi-AZ |
| Networking | VPC with public/private/database subnets |
| Security | Security Groups, NACLs, IAM Roles |
| Monitoring | CloudWatch (Logs, Metrics, Dashboards, Alarms) |
| Secrets | AWS Secrets Manager |
| IaC | Terraform 1.5+ (recommended 1.9+) |
| Application | Flask (Python 3.11) |
| Container | Docker |

## Architecture Diagram

```
                                    Internet
                                       │
                                       ▼
                              ┌─────────────────┐
                              │  Route 53 DNS   │
                              │   (Optional)    │
                              └─────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                              VPC (10.0.0.0/16)                            │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                         Internet Gateway                             ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                       │                                   │
│                                       ▼                                   │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                     Public Subnets (3 AZs)                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │  │
│  │  │     ALB      │  │     ALB      │  │     ALB      │           │  │
│  │  │   (AZ-1a)    │  │   (AZ-1b)    │  │   (AZ-1c)    │           │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │  │
│  │  │  NAT Gateway │  │  NAT Gateway │  │  NAT Gateway │           │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                       │                                   │
│                                       ▼                                   │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                  Private Subnets - App Tier (3 AZs)               │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │  │
│  │  │ EC2 Instance │  │ EC2 Instance │  │ EC2 Instance │           │  │
│  │  │  Flask App   │  │  Flask App   │  │  Flask App   │           │  │
│  │  │   (AZ-1a)    │  │   (AZ-1b)    │  │   (AZ-1c)    │           │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │  │
│  │         Auto Scaling Group (2-10 instances)                       │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                       │                                   │
│                                       ▼                                   │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                Private Subnets - Database Tier (3 AZs)            │  │
│  │  ┌──────────────┐                  ┌──────────────┐              │  │
│  │  │ RDS Primary  │ ◄──Replication──►│ RDS Standby  │              │  │
│  │  │ PostgreSQL   │                  │ PostgreSQL   │              │  │
│  │  │   (AZ-1a)    │                  │   (AZ-1b)    │              │  │
│  │  └──────────────┘                  └──────────────┘              │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
            ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
            │  CloudWatch  │  │   Secrets    │  │  VPC Flow    │
            │  Logs/Metrics│  │   Manager    │  │    Logs      │
            └──────────────┘  └──────────────┘  └──────────────┘
```

## Components

### 1. Network Layer (VPC Module)

**Purpose**: Provides isolated, secure network foundation

**Components**:
- VPC with /16 CIDR block
- 3 Availability Zones
- 9 Subnets total (3 per tier)
  - Public subnets: ALB, NAT Gateways
  - Private subnets: Application servers
  - Database subnets: RDS instances
- 1 Internet Gateway
- 3 NAT Gateways (1 per AZ for HA)
- Route tables for each tier
- VPC Flow Logs to CloudWatch
- VPC Endpoints (S3, DynamoDB)

**Key Features**:
- Network isolation between tiers
- No direct internet access from app/db tiers
- Automatic IP assignment in private subnets
- DNS resolution enabled

### 2. Security Layer (Security Module)

**Purpose**: Implements defense in depth with layered security

**Security Groups**:

1. **ALB Security Group**
   - Inbound: HTTP (80), HTTPS (443) from 0.0.0.0/0
   - Outbound: Application port to App SG only

2. **Application Security Group**
   - Inbound: Application port from ALB SG only
   - Outbound: RDS port to RDS SG, HTTPS/HTTP to internet

3. **RDS Security Group**
   - Inbound: PostgreSQL port from App SG only
   - Outbound: None (stateful)

4. **VPC Endpoints Security Group**
   - Inbound: HTTPS from VPC CIDR
   - For SSM, Secrets Manager access

**Security Principles**:
- Least privilege access
- No direct SSH access (SSM Session Manager)
- Referenced security groups (no hardcoded IPs)
- Stateful firewall rules

### 3. Compute Layer (EC2 Module)

**Purpose**: Runs application with auto-scaling capabilities

**Components**:
- Application Load Balancer (ALB)
  - Cross-zone load balancing
  - Health checks every 30 seconds
  - Connection draining (30 seconds)
  - Idle timeout: 60 seconds
  - SSL/TLS termination (optional)

- Launch Template
  - Latest Amazon Linux 2023 AMI
  - IMDSv2 enforced
  - Encrypted EBS volumes (gp3)
  - IAM instance profile
  - User data for bootstrapping

- Auto Scaling Group
  - Min: 2, Max: 10, Desired: 4 (prod)
  - Health check grace period: 300s
  - Rolling updates (90% healthy)
  - CPU-based scaling (target: 70%)
  - ALB request-based scaling (optional)

- IAM Role
  - SSM Session Manager access
  - CloudWatch Logs write
  - Secrets Manager read
  - ECR pull (if using Docker)

### 4. Database Layer (RDS Module)

**Purpose**: Managed PostgreSQL with automated backups and HA

**Configuration**:
- Engine: PostgreSQL 15.5
- Instance: db.t3.small (prod), db.t3.micro (dev)
- Storage: 100GB gp3 with autoscaling to 1TB
- Multi-AZ: Enabled (prod), Disabled (dev)
- Encrypted at rest (KMS)
- Encrypted in transit (SSL)

**Features**:
- Automated backups (30 days retention prod)
- Performance Insights enabled
- Enhanced monitoring (60s interval)
- CloudWatch Logs (postgresql, upgrade)
- Automatic minor version upgrades
- Connection pooling in application

**Credentials**:
- Stored in AWS Secrets Manager
- Automatic rotation capable
- Retrieved by application on startup

### 5. Monitoring Layer (Monitoring Module)

**Purpose**: Observability and proactive alerting

**CloudWatch Dashboard**:
- ALB metrics: Request count, latency, error rates
- EC2 metrics: CPU, network, auto-scaling
- RDS metrics: CPU, connections, storage, I/O

**CloudWatch Alarms**:
- Unhealthy target count
- High CPU (EC2, RDS)
- High error rate (5xx responses)
- Low free storage (RDS)
- Database connection count

**Log Aggregation**:
- Application logs (JSON format)
- VPC Flow Logs
- RDS logs (errors, slow queries)

**SNS Notifications**:
- Email alerts for alarms
- Integration ready for PagerDuty/Slack

## Network Design

### Subnet Strategy

**Public Subnets** (10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24)
- Internet-facing resources
- ALB, NAT Gateways
- Route to Internet Gateway

**Private Subnets** (10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24)
- Application tier
- EC2 instances
- Route to NAT Gateway for outbound

**Database Subnets** (10.0.20.0/24, 10.0.21.0/24, 10.0.22.0/24)
- Database tier (isolated)
- RDS instances
- No route to internet

### Routing

```
Public Route Table:
  0.0.0.0/0 → Internet Gateway

Private Route Table (per AZ):
  0.0.0.0/0 → NAT Gateway (in same AZ)
  10.0.0.0/16 → Local

Database Route Table:
  10.0.0.0/16 → Local
  (No internet route)
```

### IP Address Planning

- VPC CIDR: /16 (65,536 IPs)
- Subnet CIDR: /24 (256 IPs per subnet)
- Reserved: 5 IPs per subnet (AWS reserved)
- Available: 251 IPs per subnet

## Security Architecture

### Defense in Depth

**Layer 1: Network**
- VPC isolation
- Private subnets
- Security groups
- NACLs (optional)

**Layer 2: Compute**
- No SSH keys (SSM only)
- IMDSv2 enforced
- Minimal IAM permissions
- Encrypted EBS volumes

**Layer 3: Data**
- RDS encryption at rest (KMS)
- SSL/TLS in transit
- Secrets Manager for credentials
- Automated backups encrypted

**Layer 4: Application**
- Input validation
- Parameterized SQL queries
- No credentials in code
- Structured logging (no PII)

**Layer 5: Monitoring**
- VPC Flow Logs
- CloudTrail (API audit)
- CloudWatch alarms
- GuardDuty (recommended)

### Zero Trust Principles

1. **Least Privilege**: IAM roles grant minimal required permissions
2. **No Trust by Default**: All traffic filtered by security groups
3. **Verify Explicitly**: Health checks, logging, monitoring
4. **Assume Breach**: Encrypted data, isolated tiers, audit logs

## Data Flow

### Request Flow

```
1. User Request
   ↓
2. Internet → ALB (public subnet)
   ↓
3. ALB → Target Group (health check)
   ↓
4. ALB → EC2 Instance (private subnet)
   ↓
5. Application → Secrets Manager (get DB credentials)
   ↓
6. Application → RDS (database subnet)
   ↓
7. RDS → Application (query result)
   ↓
8. Application → ALB (response)
   ↓
9. ALB → User (HTTP response)
```

### Data Path Security

- **Internet to ALB**: TLS 1.2+ (if HTTPS)
- **ALB to EC2**: HTTP in private network
- **EC2 to RDS**: SSL/TLS enforced
- **EC2 to Secrets**: HTTPS over VPC endpoint

## High Availability

### Design Principles

1. **No Single Point of Failure**
   - Multi-AZ deployment
   - Redundant NAT Gateways
   - RDS Multi-AZ replication

2. **Auto-Healing**
   - ALB health checks
   - Auto Scaling Group replaces failed instances
   - RDS automatic failover

3. **Load Distribution**
   - ALB distributes across AZs
   - Cross-zone load balancing enabled

### Failure Scenarios

| Failure | Impact | Recovery |
|---------|--------|----------|
| Single EC2 Instance | None | ASG launches replacement |
| Entire AZ | 33% capacity loss | Traffic routes to healthy AZs |
| NAT Gateway | One AZ loses internet | Other AZs unaffected |
| RDS Primary | Brief downtime | Automatic failover to standby |
| ALB | N/A (multi-AZ) | AWS manages redundancy |

### Recovery Time Objectives

- **EC2 Instance Failure**: ~5 minutes (health check + launch)
- **AZ Failure**: Immediate (traffic redirects)
- **RDS Failover**: 1-2 minutes (automatic)
- **Complete Region Failure**: Manual DR required

## Scalability

### Horizontal Scaling

**Auto Scaling Policies**:

1. **CPU-Based** (Target Tracking)
   - Target: 70% CPU utilization
   - Scale out: Add instances when CPU > 70%
   - Scale in: Remove when CPU < 70%

2. **Request-Based** (Target Tracking)
   - Target: 1000 requests per instance
   - Scale based on ALB metrics

3. **Schedule-Based** (optional)
   - Scale up before peak hours
   - Scale down during off-peak

**Scaling Events**:
- Scale out: ~5 minutes (launch + health check)
- Scale in: ~30 seconds (deregistration delay)

### Vertical Scaling

Can increase instance types:
- dev: t3.micro → t3.small
- prod: t3.small → t3.medium/large

RDS can scale:
- Compute: Change instance class (requires downtime)
- Storage: Autoscaling (no downtime)

### Database Scaling

**Read Replicas** (future):
- Add read replicas for read-heavy workloads
- Application routes reads to replicas

**Connection Pooling**:
- Application uses connection pool
- Max connections: 200 (prod)

## Disaster Recovery

### Backup Strategy

**RDS**:
- Automated daily backups
- Retention: 30 days (prod), 7 days (dev)
- Point-in-time recovery
- Manual snapshots for major changes

**Infrastructure**:
- Terraform state in S3 (versioned)
- All configuration in Git
- Can recreate in ~15 minutes

### Recovery Procedures

**Scenario 1: Data Corruption**
1. Identify corruption time
2. Restore RDS from point-in-time
3. Verify data integrity
4. Update application DNS

**Scenario 2: Complete Region Failure**
1. Deploy infrastructure in new region (Terraform)
2. Restore latest RDS snapshot
3. Update DNS to new region
4. Test application

**Scenario 3: Accidental Infrastructure Deletion**
1. Restore Terraform state from S3
2. Run `terraform plan` to see changes
3. Run `terraform apply` to recreate
4. Restore RDS from snapshot

### RTO/RPO

| Scenario | RTO | RPO |
|----------|-----|-----|
| EC2 Instance Failure | 5 min | 0 |
| AZ Failure | Immediate | 0 |
| RDS Corruption | 30 min | 5 min |
| Region Failure | 2 hours | 24 hours |

## Design Decisions

### Why These Technologies?

**Terraform over CloudFormation**:
- Multi-cloud capability
- Better module ecosystem
- More readable syntax
- State management

**ALB over NLB/CLB**:
- Layer 7 routing
- Better for HTTP/HTTPS
- Advanced features (redirects, path-based routing)

**RDS over EC2 PostgreSQL**:
- Automated backups
- Automated patching
- Multi-AZ with one click
- Performance Insights

**Auto Scaling over Fixed Capacity**:
- Cost optimization
- Handles traffic spikes
- Self-healing

**SSM Session Manager over SSH**:
- No SSH keys to manage
- Audit trail in CloudTrail
- No bastion host needed
- Network independent

### Trade-offs

**Multi-AZ NAT Gateways**:
- ✅ Pro: High availability
- ❌ Con: Higher cost (~$100/month)
- Decision: Worth it for production

**RDS Multi-AZ**:
- ✅ Pro: Automatic failover
- ❌ Con: 2x database cost
- Decision: Disable in dev, enable in prod

**IMDSv2 Enforcement**:
- ✅ Pro: Security (prevents SSRF attacks)
- ❌ Con: Older tools incompatible
- Decision: Modern tools support it

## Future Enhancements

### Planned Improvements

1. **Global Deployment**
   - Multi-region with Route53 geolocation
   - Cross-region RDS replication

2. **Container Orchestration**
   - Migrate to ECS/EKS
   - Better resource utilization

3. **Caching Layer**
   - ElastiCache (Redis)
   - Reduce database load

4. **CDN**
   - CloudFront for static assets
   - Edge caching

5. **Advanced Monitoring**
   - X-Ray for distributed tracing
   - Custom metrics and anomaly detection

6. **Cost Optimization**
   - Reserved Instances
   - Savings Plans
   - Graviton instances

7. **Security Enhancements**
   - WAF for ALB
   - Shield for DDoS protection
   - GuardDuty threat detection

## References

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [12-Factor App](https://12factor.net/)

## Authors

Created and maintained by DevOps Team

## License

MIT Licensed. See LICENSE for full details.
