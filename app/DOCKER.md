# Docker Deployment Guide

Complete guide for building, running, and deploying the Flask application using Docker.

## Quick Start

### Using Docker Compose (Recommended for Development)

```bash
# Start all services (app + PostgreSQL)
docker-compose up -d

# View logs
docker-compose logs -f app

# Stop all services
docker-compose down

# Stop and remove volumes (clean slate)
docker-compose down -v
```

Application will be available at: `http://localhost:5001`

### Using Docker Only

```bash
# Build image
docker build -t demo-flask-app:latest .

# Run with PostgreSQL
docker run -d --name postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=appdb \
  -p 5432:5432 \
  postgres:15-alpine

# Run application
docker run -d --name app \
  -p 5001:5001 \
  -e DB_HOST=postgres \
  -e DB_PASSWORD=postgres \
  --link postgres:postgres \
  demo-flask-app:latest
```

## Docker Compose Services

### Services Included

1. **app** - Flask application (always started)
2. **postgres** - PostgreSQL 15 database (always started)
3. **pgadmin** - Database UI (optional, use `--profile tools`)

### Starting with Optional Services

```bash
# Start with pgAdmin
docker-compose --profile tools up -d

# Access pgAdmin at http://localhost:5050
# Email: admin@example.com
# Password: admin
```

### Service Dependencies

```
postgres (healthy) → app → ready
```

The application waits for PostgreSQL to be healthy before starting.

## Dockerfile Breakdown

### Multi-Stage Build

**Stage 1: Builder**
- Base: `python:3.11-slim`
- Installs build dependencies (gcc, postgresql-dev)
- Creates virtual environment
- Installs Python packages

**Stage 2: Runtime**
- Base: `python:3.11-slim`
- Only runtime dependencies (libpq5)
- Copies virtual environment from builder
- Runs as non-root user (`appuser`)
- Minimal attack surface

### Security Features

✅ **Multi-stage build** - Smaller final image
✅ **Non-root user** - Runs as UID 1000
✅ **Minimal dependencies** - Only what's needed
✅ **Health checks** - Automatic container monitoring
✅ **Read-only filesystem** (where possible)
✅ **No secrets in image** - All via environment variables

## Building Images

### Development Build

```bash
docker build -t demo-flask-app:dev .
```

### Production Build with Version Tag

```bash
# Set version
VERSION=1.2.3

# Build with tags
docker build \
  -t demo-flask-app:${VERSION} \
  -t demo-flask-app:latest \
  .
```

### Build with BuildKit (Faster)

```bash
DOCKER_BUILDKIT=1 docker build -t demo-flask-app:latest .
```

### Multi-Platform Build

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t demo-flask-app:latest \
  .
```

## Running Containers

### Basic Run

```bash
docker run -d \
  --name app \
  -p 5001:5001 \
  -e DB_HOST=your-db-host \
  -e DB_PASSWORD=your-password \
  demo-flask-app:latest
```

### With All Environment Variables

```bash
docker run -d \
  --name app \
  -p 5001:5001 \
  -e ENVIRONMENT=production \
  -e APP_VERSION=1.0.0 \
  -e DB_HOST=your-rds-host.amazonaws.com \
  -e DB_PORT=5432 \
  -e DB_NAME=appdb \
  -e DB_USER=dbuser \
  -e DB_PASSWORD=your-password \
  -e DB_POOL_MIN_CONN=5 \
  -e DB_POOL_MAX_CONN=20 \
  -e AWS_REGION=eu-north-1 \
  demo-flask-app:latest
```

### With Secrets Manager

```bash
docker run -d \
  --name app \
  -p 5001:5001 \
  -e ENVIRONMENT=production \
  -e AWS_REGION=eu-north-1 \
  -e DB_SECRET_ARN=arn:aws:secretsmanager:... \
  -v ~/.aws:/root/.aws:ro \
  demo-flask-app:latest
```

### With Volume Mounts

```bash
docker run -d \
  --name app \
  -p 5001:5001 \
  -e DB_HOST=postgres \
  -v $(pwd)/src:/app/src:ro \
  -v $(pwd)/logs:/var/log \
  demo-flask-app:latest
```

## Docker Compose Configuration

### Override for Development

Create `docker-compose.override.yml`:

```yaml
version: '3.8'

services:
  app:
    build:
      target: builder  # Use builder stage for dev tools
    environment:
      DEBUG: "True"
    volumes:
      - ./src:/app/src  # Hot reload
    command: python src/app.py  # Use Flask dev server
```

### Production Configuration

Create `docker-compose.prod.yml`:

```yaml
version: '3.8'

services:
  app:
    image: 123456789012.dkr.ecr.eu-north-1.amazonaws.com/demo-flask-app:latest
    restart: always
    environment:
      ENVIRONMENT: production
      DB_SECRET_ARN: ${DB_SECRET_ARN}
    deploy:
      replicas: 2
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

Use with:
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up
```

## Testing Docker Images

### Run Tests in Container

```bash
# Build test image
docker build --target builder -t demo-flask-app:test .

# Run tests
docker run --rm demo-flask-app:test pytest

# Run with coverage
docker run --rm demo-flask-app:test pytest --cov=src
```

### Security Scanning

```bash
# Scan with Trivy
trivy image demo-flask-app:latest

# Scan with Docker Scout
docker scout cves demo-flask-app:latest

# Scan with Snyk
snyk container test demo-flask-app:latest
```

### Verify Image

```bash
# Check image size
docker images demo-flask-app:latest

# Inspect image
docker inspect demo-flask-app:latest

# Check for vulnerabilities
docker scan demo-flask-app:latest
```

## Pushing to ECR

### Setup ECR

```bash
# Create repository
aws ecr create-repository \
  --repository-name demo-flask-app \
  --region eu-north-1

# Get login token
aws ecr get-login-password --region eu-north-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.eu-north-1.amazonaws.com
```

### Tag and Push

```bash
# Tag image
docker tag demo-flask-app:latest \
  123456789012.dkr.ecr.eu-north-1.amazonaws.com/demo-flask-app:latest

docker tag demo-flask-app:latest \
  123456789012.dkr.ecr.eu-north-1.amazonaws.com/demo-flask-app:1.0.0

# Push image
docker push 123456789012.dkr.ecr.eu-north-1.amazonaws.com/demo-flask-app:latest
docker push 123456789012.dkr.ecr.eu-north-1.amazonaws.com/demo-flask-app:1.0.0
```

## Health Checks

### Docker Health Check

Built into Dockerfile:
```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:5001/health || exit 1
```

### Check Container Health

```bash
# View health status
docker ps

# Detailed health check logs
docker inspect --format='{{json .State.Health}}' app | jq .
```

### Manual Health Check

```bash
docker exec app curl -f http://localhost:5001/health
```

## Logs

### View Logs

```bash
# Follow logs
docker-compose logs -f app

# Last 100 lines
docker-compose logs --tail=100 app

# Logs for specific time range
docker-compose logs --since 30m app
```

### Log to File

```bash
docker-compose logs app > app.log
```

### JSON Logs

Application outputs JSON logs for easy parsing:

```bash
docker-compose logs app | jq 'select(.level == "ERROR")'
```

## Debugging

### Access Container Shell

```bash
# Using docker-compose
docker-compose exec app /bin/sh

# Using docker
docker exec -it app /bin/sh
```

### Run Commands in Container

```bash
# Check database connectivity
docker-compose exec app psql -h postgres -U postgres -d appdb -c "SELECT 1"

# Check Python environment
docker-compose exec app python --version

# View environment variables
docker-compose exec app env
```

### Debug Mode

```bash
# Start with debug enabled
docker run -it --rm \
  -p 5001:5001 \
  -e DEBUG=True \
  demo-flask-app:latest
```

## Performance Optimization

### Reduce Image Size

Current image size: ~150MB

**Tips**:
1. Use multi-stage builds ✅ (Already implemented)
2. Use Alpine base images (consider security trade-offs)
3. Remove unnecessary files
4. Combine RUN commands

### Build Cache Optimization

Order matters in Dockerfile:
1. Install dependencies (rarely changes)
2. Copy code (changes frequently)

```dockerfile
# Good - dependencies cached
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY src/ ./src/

# Bad - cache invalidated on code change
COPY . .
RUN pip install -r requirements.txt
```

### Runtime Performance

**Gunicorn workers**:
```bash
# Formula: (2 x CPU cores) + 1
# For 1 CPU
--workers 3

# For 2 CPUs
--workers 5
```

**Worker class**:
- `sync` - Default, good for CPU-bound
- `gevent` - Better for I/O-bound
- `eventlet` - Alternative async

## Troubleshooting

### Container Won't Start

**Check logs**:
```bash
docker logs app
```

**Common issues**:
1. Database not ready - Wait for health check
2. Port already in use - Change port mapping
3. Environment variables missing - Check `.env`

### Database Connection Failed

```bash
# Check network connectivity
docker-compose exec app ping postgres

# Test database directly
docker-compose exec postgres psql -U postgres -d appdb -c "SELECT 1"

# Check credentials
docker-compose exec app env | grep DB_
```

### High Memory Usage

```bash
# Check container stats
docker stats app

# Set memory limits
docker run -m 512m demo-flask-app:latest
```

### Permission Denied

Application runs as non-root user (UID 1000).

**Fix volume permissions**:
```bash
chown -R 1000:1000 ./logs
```

## Production Considerations

### Resource Limits

```yaml
services:
  app:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

### Restart Policy

```yaml
services:
  app:
    restart: unless-stopped
```

### Logging Driver

```yaml
services:
  app:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### Secrets Management

**Don't use in production**:
```yaml
environment:
  DB_PASSWORD: mysecretpassword  # ❌
```

**Use instead**:
```yaml
environment:
  DB_SECRET_ARN: ${DB_SECRET_ARN}  # ✅
```

Or Docker secrets:
```yaml
secrets:
  db_password:
    external: true
```

## CI/CD Integration

See `.github/workflows/app-deploy.yml` for complete CI/CD pipeline that:
1. Builds Docker image
2. Scans for vulnerabilities
3. Pushes to ECR
4. Deploys to EC2

## Additional Resources

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Dockerfile Reference](https://docs.docker.com/engine/reference/builder/)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)
- [Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)

## License

MIT Licensed. See LICENSE for full details.
