# How It All Works - Complete System Explanation

This document explains how all the components work together.

## High-Level Overview

```
Internet
   ↓
Route 53 (DNS) [optional]
   ↓
Application Load Balancer (ALB)
   ↓
Auto Scaling Group
   ├── EC2 Instance 1 (AZ-1)
   ├── EC2 Instance 2 (AZ-2)
   └── EC2 Instance N
        ↓
        Flask Application
             ↓
        RDS PostgreSQL (Multi-AZ)
```

---

## 1. Network Layer (VPC Module)

### What Happens

When you deploy, Terraform creates:

1. **VPC** (10.0.0.0/16)
   - Isolated network in AWS
   - Can hold 65,536 IP addresses

2. **Subnets** (3-tier architecture):
   ```
   Public Subnets (10.0.0-2.0/24):
   ├── ALB instances
   └── NAT Gateways
   
   Private Subnets (10.0.10-12.0/24):
   ├── EC2 application instances
   └── Can reach internet via NAT
   
   Database Subnets (10.0.20-22.0/24):
   └── RDS instances (isolated, no internet)
   ```

3. **Internet Gateway**:
   - Allows ALB to accept requests from internet
   - Public subnets route 0.0.0.0/0 → IGW

4. **NAT Gateway**:
   - Allows EC2 instances to download packages
   - Private subnets route 0.0.0.0/0 → NAT
   - NAT is in public subnet, uses IGW

### Why This Design?

- **Security**: Apps can't be directly accessed from internet
- **Updates**: Apps can download updates via NAT
- **Database Isolation**: RDS has no internet access at all
- **High Availability**: Resources spread across multiple AZs

---

## 2. Security Layer (Security Module)

### How Security Groups Work

Security Groups are **stateful firewalls** attached to resources:

```
Internet → ALB Security Group → App Security Group → RDS Security Group
          (allows 80/443)      (allows app port)    (allows 5432)
                                from ALB only        from app only
```

### Key Security Principle: Referenced Security Groups

Instead of:
```hcl
# BAD: Hardcoded IPs
allow port 5432 from 10.0.10.0/24  # What if subnet changes?
```

We use:
```hcl
# GOOD: Referenced security group
allow port 5432 from sg-app  # Always works, no IPs!
```

### What This Means

- **ALB** can only talk to **App** (not RDS directly)
- **App** can only talk to **RDS** (not other apps)
- **RDS** accepts connections only from **App** (never from internet)
- If you add more instances, security groups automatically apply

---

## 3. Database Layer (RDS Module)

### What Gets Created

1. **RDS Instance**:
   - PostgreSQL 15
   - Multi-AZ (in prod): Primary in AZ-1, standby in AZ-2
   - Automated backups every day
   - Encrypted with KMS

2. **Secrets Manager**:
   - Stores database credentials securely
   - Application retrieves at runtime
   - No passwords in code or environment variables

3. **Parameter Group**:
   - Custom PostgreSQL settings
   - Optimized for workload

4. **Subnet Group**:
   - Tells RDS which subnets it can use
   - Spans multiple AZs for failover

### How Multi-AZ Works

```
Normal Operation:
AZ-1: RDS Primary (active) ←── Application connects here
AZ-2: RDS Standby (passive)    Continuously replicates

Failure Scenario:
AZ-1: RDS Primary (FAILS!)
AZ-2: RDS Standby → Promoted to Primary ←── Application automatically reconnects
      (Downtime: 60-120 seconds)
```

### Backup Strategy

- **Automated Backups**: Daily, kept for 30 days (prod) or 1 day (dev)
- **Point-in-Time Recovery**: Can restore to any second in retention window
- **Final Snapshot**: Created before deletion
- **Encrypted**: All backups encrypted with KMS

---

## 4. Compute Layer (EC2 Module)

### Application Load Balancer (ALB)

**What it does:**
1. Receives HTTP/HTTPS requests from internet
2. Checks which instances are healthy
3. Distributes requests across healthy instances
4. Returns responses to clients

**Health Checks:**
```
Every 30 seconds:
ALB → GET /health on each instance
      └── If 200 OK: Instance is healthy
      └── If 500 or timeout: Instance is unhealthy
      
If unhealthy for 2 consecutive checks:
└── Stop sending traffic to that instance
```

### Auto Scaling Group (ASG)

**What it does:**
1. Maintains desired number of instances
2. Replaces failed instances automatically
3. Scales up when CPU > 70%
4. Scales down when CPU < 30%

**Launch Template:**
- Defines how to launch new instances
- Includes AMI, instance type, security groups, user data

**User Data Script:**
- Runs on instance first boot
- Installs Docker
- Pulls application image from ECR (or builds locally)
- Starts Flask application
- Configures CloudWatch agent
- Retrieves DB credentials from Secrets Manager

**Scaling Behavior:**
```
Scenario: High Traffic

1. CPU usage exceeds 70%
2. CloudWatch alarm triggers
3. ASG launches new instance
4. Instance runs user data script (3-5 minutes)
5. Instance becomes healthy
6. ALB starts sending traffic to it
7. CPU usage drops below 70%
```

### How Instances Get Database Credentials

```bash
# User data script runs on instance startup:

# 1. Get credentials from Secrets Manager
DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id demo-flask-app-dev-db-credentials \
  --query SecretString \
  --output text)

# 2. Parse JSON
DB_HOST=$(echo $DB_SECRET | jq -r '.host')
DB_PASSWORD=$(echo $DB_SECRET | jq -r '.password')

# 3. Pass to application via environment variables
export DB_HOST=$DB_HOST
export DB_PASSWORD=$DB_PASSWORD

# 4. Start application
docker run -e DB_HOST -e DB_PASSWORD ...
```

**Why this is secure:**
- ✅ No credentials in code
- ✅ No credentials in Terraform state
- ✅ Credentials rotatable without changing code
- ✅ Audit trail in CloudWatch (who accessed secrets)

---

## 5. Application Layer (Flask App)

### Application Architecture

```python
# Flask application structure

app.py
├── Configuration (reads environment variables)
├── Database connection pool (2-10 connections)
├── Routes
│   ├── GET / (basic info)
│   ├── GET /health (with DB check)
│   ├── GET /db (database stats)
│   ├── GET /api/items (list items)
│   ├── POST /api/items (create item)
│   └── GET /metrics (Prometheus format)
├── JSON logging (CloudWatch-compatible)
└── Graceful shutdown (SIGTERM handler)
```

### Connection Pooling

**Without pooling:**
```
Request 1 → Open DB connection → Query → Close connection
Request 2 → Open DB connection → Query → Close connection
Request 3 → Open DB connection → Query → Close connection
(Slow! Opening connections takes time)
```

**With pooling:**
```
Startup: Open 2 connections (always available)

Request 1 → Get connection from pool → Query → Return to pool
Request 2 → Get connection from pool → Query → Return to pool
Request 3 → Get connection from pool → Query → Return to pool
(Fast! Connections already open)

Max 10 connections (prevents overwhelming database)
```

### JSON Logging

All logs are structured JSON for easy CloudWatch parsing:

```json
{
  "timestamp": "2024-11-01T12:00:00Z",
  "level": "INFO",
  "msg": "Request completed",
  "method": "GET",
  "path": "/api/items",
  "status": 200,
  "response_time_ms": 45,
  "instance_id": "i-1234567890abcdef0"
}
```

**Benefits:**
- Easy to search: `filter level = "ERROR"`
- Easy to aggregate: `stats count() by status`
- Machine-readable for alerts

---

## 6. Monitoring Layer (CloudWatch)

### CloudWatch Dashboard

Shows real-time metrics:

**ALB Metrics:**
- Request count (how many requests/minute)
- Response time (p50, p95, p99)
- HTTP status codes (200s, 400s, 500s)
- Healthy vs unhealthy targets

**ASG Metrics:**
- Desired capacity (what ASG wants)
- In-service instances (what's actually running)
- CPU utilization

**RDS Metrics:**
- CPU usage
- Database connections
- Free storage space
- Read/write latency

### CloudWatch Alarms

Monitors and alerts on issues:

**Critical Alarms** (sends email + SMS):
- Unhealthy hosts > 0 for 5 minutes
- 5xx errors > 50 in 5 minutes
- Database CPU > 90% for 10 minutes

**Warning Alarms** (email only):
- CPU > 70% for 15 minutes
- Storage < 10GB

**Alarm Behavior:**
```
Normal State: OK (green)
   ↓
Metric exceeds threshold
   ↓
State: ALARM (red)
   ↓
SNS publishes to topic
   ↓
Email sent to you
   ↓
Manual fix or auto-recovery
   ↓
State: OK (green)
```

### Log Metric Filters

Automatically count specific log patterns:

```
Log: {"level": "ERROR", "msg": "Database connection failed"}
     ↓
Metric Filter: count all level=ERROR
     ↓
Custom Metric: ErrorCount +1
     ↓
Alarm: If ErrorCount > 10 in 5 min → Send alert
```

---

## 7. CI/CD Pipeline (GitHub Actions)

### Workflow: Code → Production

```
Developer pushes code to GitHub
   ↓
GitHub Actions triggered
   ↓
╔═══════════════════════════════════╗
║  Job 1: Tests                     ║
║  - Terraform fmt/validate         ║
║  - Python linting (flake8, black) ║
║  - pytest unit tests              ║
║  - Docker build test              ║
╚═══════════════════════════════════╝
   ↓ (if tests pass)
╔═══════════════════════════════════╗
║  Job 2: Build                     ║
║  - Build Docker image             ║
║  - Scan with Trivy                ║
║  - Push to ECR                    ║
╚═══════════════════════════════════╝
   ↓ (if main branch)
╔═══════════════════════════════════╗
║  Job 3: Deploy (Dev)              ║
║  - Trigger ASG instance refresh   ║
║  - Wait for new instances         ║
║  - Run smoke tests                ║
╚═══════════════════════════════════╝
```

### Instance Refresh (Blue-Green Deployment)

```
Current State:
Instance A (old version) ──┐
Instance B (old version) ──┼──> ALB
                           │
Instance Refresh Started:   │
                           │
1. Launch Instance C (new) ─┤
2. Wait for health check    │
3. Drain Instance A         │
4. Terminate Instance A     │
                           │
Instance B (old) ──────────┼──> ALB
Instance C (new) ──────────┘
                           
5. Launch Instance D (new) ─┐
6. Wait for health check    │
7. Drain Instance B         │
8. Terminate Instance B     │
                           │
New State:                  │
Instance C (new) ──────────┼──> ALB
Instance D (new) ──────────┘
```

**Benefits:**
- Zero downtime
- Always maintain 90% capacity
- Automatic rollback if health checks fail

---

## 8. Complete Request Flow

### User Makes Request

```
1. User types: http://my-alb-123.eu-north-1.elb.amazonaws.com/api/items
   ↓
2. DNS resolves to ALB IP: 52.12.34.56
   ↓
3. Request hits ALB
   ↓
4. ALB checks: Which instances are healthy?
   └── Instance A: Healthy ✓
   └── Instance B: Healthy ✓
   └── Instance C: Unhealthy ✗ (skip this one)
   ↓
5. ALB picks Instance A (round-robin)
   ↓
6. ALB forwards request to Instance A (private IP: 10.0.10.45:5001)
   ↓
7. Instance A: Flask application receives request
   ↓
8. Flask: Get connection from pool
   ↓
9. Flask: Query database
   └── SELECT * FROM items;
   ↓
10. RDS: Returns results
    ↓
11. Flask: Format as JSON, log to CloudWatch
    ↓
12. Flask: Return response to ALB
    ↓
13. ALB: Forward response to user
    ↓
14. User sees:
    {
      "items": [
        {"id": 1, "name": "Item 1", "description": "First item"}
      ]
    }
```

**Timing:**
- ALB routing: ~1ms
- Application processing: ~10-50ms
- Database query: ~5-20ms
- Total: ~20-70ms (very fast!)

---

## 9. Failure Scenarios & Recovery

### Scenario 1: Single Instance Fails

```
Current: 2 instances healthy
   ↓
Instance A crashes (hardware failure)
   ↓
ALB health check fails (2 consecutive checks = 60 seconds)
   ↓
ALB stops sending traffic to Instance A
   ↓
ASG detects instance failure
   ↓
ASG launches replacement Instance C
   ↓
Instance C starts (user data runs, ~3 minutes)
   ↓
ALB health check succeeds
   ↓
ALB starts sending traffic to Instance C
   ↓
ASG terminates failed Instance A
   ↓
Back to 2 healthy instances

Downtime: NONE (Instance B handled all traffic)
```

### Scenario 2: Database Primary Fails

```
Current: Primary in AZ-1, Standby in AZ-2
   ↓
AZ-1 has outage (power failure)
   ↓
RDS detects primary failure (health checks)
   ↓
RDS promotes Standby to Primary (~60-120 seconds)
   ↓
RDS updates DNS: endpoint now points to new primary
   ↓
Application connection pool detects disconnect
   ↓
Application reconnects using same endpoint (DNS resolved)
   ↓
Application now connected to new primary
   ↓
Service restored

Downtime: 60-120 seconds (time for failover)
Error rate: ~10-20 requests failed during failover
```

### Scenario 3: Entire AZ Fails

```
Current: Resources in AZ-1 and AZ-2
   ↓
AZ-1 completely fails
   ↓
ALB stops routing to AZ-1 instances
   ↓
All traffic goes to AZ-2 instances
   ↓
CPU increases on AZ-2 instances
   ↓
Auto Scaling launches additional instances in AZ-2
   ↓
Service continues (degraded performance for 3-5 minutes)
   ↓
AZ-1 recovers
   ↓
ASG launches instances in AZ-1 again
   ↓
Traffic distributes across both AZs

Downtime: NONE (other AZ took over)
Performance: Degraded for 3-5 minutes
```

---

## 10. Cost Breakdown

### What You're Paying For

**Compute:**
- EC2 instances (2x t3.micro): $0.021/hour
  - Running your application
  - Always on (24/7)

**Networking:**
- NAT Gateway: $0.045/hour
  - Allows instances to download updates
  - Per-AZ charge + data transfer
- ALB: $0.0225/hour
  - Distributes traffic
  - LCU charges for high traffic

**Database:**
- RDS (db.t3.micro): $0.017/hour
  - PostgreSQL database
  - Storage: $0.115/GB-month
  - Backup storage: Free for 30-day retention

**Monitoring:**
- CloudWatch Logs: $0.50/GB ingested
- CloudWatch Metrics: Custom metrics $0.30/metric
- CloudWatch Alarms: $0.10/alarm

**Storage:**
- EBS volumes: $0.10/GB-month
- S3 (Terraform state): $0.023/GB-month

### Cost Optimization Tips

**For Testing (2-3 hours):**
- Use t3.micro instances ✓
- Single NAT Gateway ✓
- Minimum instances (1) ✓
- Small RDS (db.t3.micro) ✓
- **Total: ~$0.42 for 3 hours**

**For Production:**
- Use t3.small or larger
- Multiple NAT Gateways (HA)
- Multiple instances (2-10)
- Larger RDS with Multi-AZ
- Reserved Instances (40% savings)
- Savings Plans (up to 72% savings)

**Cost Alerts:**
```bash
# Set up billing alert (once)
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget.json

# budget.json
{
  "BudgetLimit": {
    "Amount": "10",
    "Unit": "USD"
  },
  "BudgetName": "Monthly-Budget",
  "BudgetType": "COST",
  "TimeUnit": "MONTHLY"
}
```

---

## 11. Security Deep Dive

### Defense in Depth Layers

**Layer 1: Network (VPC)**
- Private subnets (no direct internet access)
- Network ACLs (subnet-level firewall)
- VPC Flow Logs (network traffic audit)

**Layer 2: Security Groups**
- Stateful firewall
- Least privilege rules
- Referenced security groups (no hardcoded IPs)

**Layer 3: IAM Roles**
- EC2 role: Only SSM, Secrets Manager, CloudWatch
- RDS role: Only enhanced monitoring
- No long-term credentials

**Layer 4: Encryption**
- Data at rest: KMS encryption (RDS, EBS)
- Data in transit: TLS 1.2+ (ALB, RDS)
- Secrets: Encrypted in Secrets Manager

**Layer 5: Application**
- Input validation
- SQL injection prevention (parameterized queries)
- CSRF protection
- Rate limiting (via ALB)

**Layer 6: Monitoring**
- CloudWatch Logs (all actions logged)
- CloudTrail (all API calls logged)
- VPC Flow Logs (all network traffic logged)
- Alarms (detect anomalies)

### Why No SSH?

Traditional approach:
```
Developer → SSH (port 22) → EC2 instance
Problems:
- Need SSH keys (can be stolen)
- Port 22 open (attack vector)
- No audit trail (who did what?)
```

Our approach:
```
Developer → AWS SSM Session Manager → EC2 instance
Benefits:
- No SSH keys needed
- No open port 22
- All sessions logged to CloudWatch
- MFA can be enforced
- Temporary credentials only
```

---

## Summary: How to Think About This System

**The Infrastructure is Like a Restaurant:**

- **VPC** = The building (isolated space)
- **Subnets** = Different rooms (kitchen, dining, storage)
- **Internet Gateway** = Front door (customers enter)
- **NAT Gateway** = Delivery entrance (supplies come in)
- **ALB** = Host/Hostess (greets customers, assigns tables)
- **EC2 Instances** = Waiters (serve customers)
- **RDS** = Kitchen (prepares orders)
- **Security Groups** = Doors between rooms (controlled access)
- **CloudWatch** = Security cameras (monitor everything)
- **Auto Scaling** = Hiring more waiters when busy

**A Customer Order (HTTP Request):**
1. Customer enters (hits ALB)
2. Host assigns table (ALB picks instance)
3. Waiter takes order (Flask receives request)
4. Kitchen prepares food (RDS queries data)
5. Waiter serves food (Flask returns response)
6. Customer happy! (200 OK)

**When Kitchen Breaks (Database Fails):**
- Backup kitchen activates (Multi-AZ failover)
- Slight delay (60 seconds)
- Service continues

**When Too Busy (High Traffic):**
- Hire more waiters (Auto Scaling launches instances)
- Takes a few minutes (instance startup)
- Then handle more customers

---

**You now understand how everything works! 🎉**

For deployment instructions, see: QUICK_START.md or DEPLOYMENT_GUIDE.md
