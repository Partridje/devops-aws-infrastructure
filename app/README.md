# Demo Flask Application

Production-ready Flask application with PostgreSQL integration, health checks, metrics, and structured logging.

## Features

- ✅ **RESTful API**: CRUD operations for items
- ✅ **PostgreSQL Integration**: Connection pooling and automatic table creation
- ✅ **AWS Secrets Manager**: Secure credential management
- ✅ **Health Checks**: Liveness and readiness probes
- ✅ **Prometheus Metrics**: Request count, errors, and custom metrics
- ✅ **Structured Logging**: JSON logs for CloudWatch
- ✅ **Graceful Shutdown**: Proper cleanup on termination
- ✅ **Database Migrations**: Automatic table creation
- ✅ **Error Handling**: Global exception handlers

## API Endpoints

### Health & Info

#### `GET /`
Basic health check and instance information.

**Response**:
```json
{
  "status": "healthy",
  "service": "demo-flask-app",
  "version": "1.0.0",
  "environment": "dev",
  "hostname": "ip-10-0-1-123",
  "instance_id": "i-1234567890abcdef0",
  "instance_ip": "10.0.1.123",
  "availability_zone": "eu-north-1a",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

#### `GET /health`
Detailed health check with database connectivity.

**Response**:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "1.0.0",
  "checks": {
    "application": "ok",
    "database": "ok"
  },
  "instance": {
    "id": "i-1234567890abcdef0",
    "ip": "10.0.1.123",
    "az": "eu-north-1a"
  }
}
```

#### `GET /db`
Database connectivity and statistics.

**Response**:
```json
{
  "status": "connected",
  "database_version": "PostgreSQL 15.5",
  "tables_count": 1,
  "items_count": 42,
  "pool_size": 10
}
```

#### `GET /metrics`
Prometheus-style metrics.

**Response** (text/plain):
```
application_info{version="1.0.0",environment="dev",instance="i-123"} 1
application_up 1
http_requests_total 1234
http_errors_total 5
db_pool_size 10
```

### Items API

#### `GET /api/items`
Retrieve all items with pagination.

**Query Parameters**:
- `limit` (optional): Number of items to return (default: 100)
- `offset` (optional): Number of items to skip (default: 0)

**Example**:
```bash
curl http://localhost:5001/api/items?limit=10&offset=0
```

**Response**:
```json
{
  "items": [
    {
      "id": 1,
      "name": "Example Item",
      "description": "This is an example",
      "value": "123",
      "created_at": "2024-01-15T10:00:00",
      "updated_at": "2024-01-15T10:00:00"
    }
  ],
  "count": 1,
  "limit": 10,
  "offset": 0
}
```

#### `POST /api/items`
Create a new item.

**Request Body**:
```json
{
  "name": "New Item",
  "description": "Optional description",
  "value": "Optional value"
}
```

**Example**:
```bash
curl -X POST http://localhost:5001/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Item","description":"A test","value":"42"}'
```

**Response**:
```json
{
  "message": "Item created successfully",
  "item": {
    "id": 2,
    "name": "New Item",
    "description": "Optional description",
    "value": "Optional value",
    "created_at": "2024-01-15T10:30:00"
  }
}
```

## Configuration

The application is configured via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `APPLICATION_PORT` | Port to listen on | `5001` |
| `ENVIRONMENT` | Environment name | `dev` |
| `APP_VERSION` | Application version | `1.0.0` |
| `AWS_REGION` | AWS region | `eu-north-1` |
| `DB_HOST` | Database host | `localhost` |
| `DB_PORT` | Database port | `5432` |
| `DB_NAME` | Database name | `appdb` |
| `DB_USER` | Database user | `postgres` |
| `DB_PASSWORD` | Database password | `""` |
| `DB_SECRET_ARN` | Secrets Manager ARN (overrides DB_*) | `""` |
| `DB_POOL_MIN_CONN` | Min connections in pool | `2` |
| `DB_POOL_MAX_CONN` | Max connections in pool | `10` |
| `INSTANCE_ID` | EC2 instance ID | hostname |
| `INSTANCE_IP` | Instance IP address | `127.0.0.1` |
| `AVAILABILITY_ZONE` | Availability zone | `local` |
| `DEBUG` | Enable debug mode | `False` |

## Local Development

### Prerequisites
- Python 3.11+
- PostgreSQL 15+
- pip

### Setup

1. **Create virtual environment**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Start PostgreSQL** (using Docker):
   ```bash
   docker run -d \
     --name postgres \
     -e POSTGRES_PASSWORD=postgres \
     -e POSTGRES_DB=appdb \
     -p 5432:5432 \
     postgres:15
   ```

4. **Set environment variables**:
   ```bash
   export DB_HOST=localhost
   export DB_PORT=5432
   export DB_NAME=appdb
   export DB_USER=postgres
   export DB_PASSWORD=postgres
   export ENVIRONMENT=dev
   export DEBUG=True
   ```

5. **Run the application**:
   ```bash
   python src/app.py
   ```

6. **Test the endpoints**:
   ```bash
   # Health check
   curl http://localhost:5001/health

   # Create an item
   curl -X POST http://localhost:5001/api/items \
     -H "Content-Type: application/json" \
     -d '{"name":"Test","description":"Hello"}'

   # Get items
   curl http://localhost:5001/api/items
   ```

## Production Deployment

### Using Gunicorn

```bash
gunicorn \
  --bind 0.0.0.0:5001 \
  --workers 4 \
  --timeout 120 \
  --access-logfile - \
  --error-logfile - \
  --log-level info \
  src.app:app
```

### Environment Variables (Production)

```bash
export ENVIRONMENT=prod
export DEBUG=False
export DB_SECRET_ARN=arn:aws:secretsmanager:eu-north-1:123456789012:secret:myapp-db-credentials-xxx
export AWS_REGION=eu-north-1
export APPLICATION_PORT=5001
export DB_POOL_MIN_CONN=5
export DB_POOL_MAX_CONN=20
```

## Docker

See [Dockerfile](Dockerfile) for containerized deployment.

```bash
# Build
docker build -t demo-flask-app:latest .

# Run
docker run -d \
  -p 5001:5001 \
  -e DB_HOST=your-rds-host \
  -e DB_NAME=appdb \
  -e DB_USER=dbuser \
  -e DB_PASSWORD=dbpass \
  demo-flask-app:latest
```

## Testing

### Run Tests

```bash
# Install dev dependencies
pip install -r requirements.txt

# Run tests
pytest

# Run with coverage
pytest --cov=src --cov-report=html

# View coverage report
open htmlcov/index.html
```

### Manual Testing

```bash
# Health checks
curl http://localhost:5001/health
curl http://localhost:5001/db

# Create test data
for i in {1..10}; do
  curl -X POST http://localhost:5001/api/items \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Item $i\",\"value\":\"$i\"}"
done

# Retrieve items
curl http://localhost:5001/api/items

# Check metrics
curl http://localhost:5001/metrics
```

## Logging

The application uses structured JSON logging for easy parsing by CloudWatch:

```json
{
  "timestamp": "2024-01-15T10:30:00.123Z",
  "level": "INFO",
  "logger": "__main__",
  "message": "GET /api/items 200",
  "module": "app",
  "function": "after_request",
  "line": 156,
  "request_id": "i-123-1705318200.123",
  "method": "GET",
  "path": "/api/items",
  "status": 200,
  "duration_ms": 45.23
}
```

## Database Schema

### Items Table

```sql
CREATE TABLE items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    value VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_items_created_at ON items(created_at DESC);
```

## Troubleshooting

### Database Connection Issues

**Problem**: Cannot connect to database

**Solution**:
1. Check database is running:
   ```bash
   psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT 1"
   ```

2. Verify security groups allow traffic on port 5432

3. Check Secrets Manager permissions:
   ```bash
   aws secretsmanager get-secret-value --secret-id $DB_SECRET_ARN
   ```

### Health Check Failing

**Problem**: `/health` returns 503

**Solution**:
1. Check application logs:
   ```bash
   docker logs <container-id>
   ```

2. Test database connectivity:
   ```bash
   curl http://localhost:5001/db
   ```

3. Check connection pool:
   ```bash
   curl http://localhost:5001/metrics | grep db_pool
   ```

### High Memory Usage

**Problem**: Application consuming too much memory

**Solution**:
1. Reduce connection pool size:
   ```bash
   export DB_POOL_MAX_CONN=5
   ```

2. Reduce Gunicorn workers:
   ```bash
   gunicorn --workers 2 ...
   ```

## Performance Tuning

### Connection Pooling

Adjust based on your workload:

```python
# Low traffic (dev)
DB_POOL_MIN_CONN=2
DB_POOL_MAX_CONN=10

# Medium traffic (staging)
DB_POOL_MIN_CONN=5
DB_POOL_MAX_CONN=20

# High traffic (production)
DB_POOL_MIN_CONN=10
DB_POOL_MAX_CONN=50
```

### Gunicorn Workers

Formula: `workers = (2 x CPU_cores) + 1`

```bash
# For t3.small (2 vCPUs)
gunicorn --workers 5 ...

# For t3.medium (2 vCPUs)
gunicorn --workers 5 ...

# For t3.large (2 vCPUs)
gunicorn --workers 5 ...
```

## Security

- ✅ No credentials in code
- ✅ Secrets Manager integration
- ✅ SQL injection prevention (parameterized queries)
- ✅ Input validation
- ✅ Error messages don't expose internals
- ✅ Structured logging (no sensitive data)

## License

MIT Licensed. See LICENSE for full details.
