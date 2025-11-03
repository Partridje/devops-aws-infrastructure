"""
Production-Ready Flask Application
===================================
Demo application for AWS infrastructure with:
- PostgreSQL database integration
- Health check endpoints
- Prometheus metrics
- Structured JSON logging
- Graceful shutdown
- AWS Secrets Manager integration
"""

import os
import sys
import json
import socket
import signal
import logging
from datetime import datetime
from typing import Dict, Any, Optional

import psycopg2
from psycopg2 import pool
from flask import Flask, jsonify, request, Response
from werkzeug.exceptions import HTTPException
import boto3
from botocore.exceptions import ClientError

# =============================================================================
# Configuration
# =============================================================================

class Config:
    """Application configuration from environment variables"""

    # Flask settings
    FLASK_ENV = os.getenv('FLASK_ENV', 'production')
    DEBUG = os.getenv('DEBUG', 'False').lower() == 'true'

    # Application settings
    APPLICATION_PORT = int(os.getenv('APPLICATION_PORT', 5001))
    ENVIRONMENT = os.getenv('ENVIRONMENT', 'dev')
    APP_VERSION = os.getenv('APP_VERSION', '1.0.0')

    # AWS settings
    AWS_REGION = os.getenv('AWS_REGION', 'eu-north-1')

    # Database settings (can be overridden by Secrets Manager)
    DB_HOST = os.getenv('DB_HOST', 'localhost')
    DB_PORT = int(os.getenv('DB_PORT', 5432))
    DB_NAME = os.getenv('DB_NAME', 'appdb')
    DB_USER = os.getenv('DB_USER', 'postgres')
    DB_PASSWORD = os.getenv('DB_PASSWORD', '')

    # Connection pool settings
    DB_POOL_MIN_CONN = int(os.getenv('DB_POOL_MIN_CONN', 2))
    DB_POOL_MAX_CONN = int(os.getenv('DB_POOL_MAX_CONN', 10))

    # Instance metadata
    INSTANCE_ID = os.getenv('INSTANCE_ID', socket.gethostname())
    INSTANCE_IP = os.getenv('INSTANCE_IP', '127.0.0.1')
    AVAILABILITY_ZONE = os.getenv('AVAILABILITY_ZONE', 'local')

# =============================================================================
# Logging Configuration
# =============================================================================

class JsonFormatter(logging.Formatter):
    """Custom JSON formatter for structured logging"""

    def format(self, record: logging.LogRecord) -> str:
        log_data = {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
            'module': record.module,
            'function': record.funcName,
            'line': record.lineno,
        }

        # Add exception info if present
        if record.exc_info:
            log_data['exception'] = self.formatException(record.exc_info)

        # Add extra fields
        if hasattr(record, 'request_id'):
            log_data['request_id'] = record.request_id

        return json.dumps(log_data)

def setup_logging():
    """Configure structured JSON logging"""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO if not Config.DEBUG else logging.DEBUG)

    # Suppress noisy loggers
    logging.getLogger('werkzeug').setLevel(logging.WARNING)

    return logging.getLogger(__name__)

logger = setup_logging()

# =============================================================================
# Database Connection Pool
# =============================================================================

class DatabasePool:
    """PostgreSQL connection pool manager"""

    def __init__(self):
        self.pool: Optional[pool.SimpleConnectionPool] = None
        self._initialized = False

    def initialize(self):
        """Initialize database connection pool"""
        if self._initialized:
            return

        try:
            # Try to get credentials from Secrets Manager
            db_config = self._get_db_credentials_from_secrets_manager()

            # Fallback to environment variables
            if not db_config:
                db_config = {
                    'host': Config.DB_HOST,
                    'port': Config.DB_PORT,
                    'database': Config.DB_NAME,
                    'user': Config.DB_USER,
                    'password': Config.DB_PASSWORD
                }

            logger.info(f"Initializing database pool: {db_config['host']}:{db_config['port']}/{db_config['database']}")

            self.pool = pool.SimpleConnectionPool(
                Config.DB_POOL_MIN_CONN,
                Config.DB_POOL_MAX_CONN,
                **db_config,
                connect_timeout=10
            )

            # Test connection and create table
            self._create_tables()
            self._initialized = True

            logger.info("Database pool initialized successfully")

        except Exception as e:
            logger.error(f"Failed to initialize database pool: {e}")
            self.pool = None

    def _get_db_credentials_from_secrets_manager(self) -> Optional[Dict[str, Any]]:
        """Retrieve database credentials from AWS Secrets Manager"""
        secret_arn = os.getenv('DB_SECRET_ARN', '')

        if not secret_arn:
            logger.info("No DB_SECRET_ARN provided, using environment variables")
            return None

        try:
            session = boto3.session.Session()
            client = session.client(
                service_name='secretsmanager',
                region_name=Config.AWS_REGION
            )

            response = client.get_secret_value(SecretId=secret_arn)
            secret = json.loads(response['SecretString'])

            logger.info("Successfully retrieved database credentials from Secrets Manager")

            return {
                'host': secret.get('host'),
                'port': int(secret.get('port', 5432)),
                'database': secret.get('dbname'),
                'user': secret.get('username'),
                'password': secret.get('password')
            }

        except ClientError as e:
            logger.error(f"Failed to retrieve secret from Secrets Manager: {e}")
            return None

    def _create_tables(self):
        """Create application tables if they don't exist"""
        conn = None
        try:
            conn = self.get_connection()
            cursor = conn.cursor()

            # Create items table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS items (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(255) NOT NULL,
                    description TEXT,
                    value VARCHAR(255),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Create index
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_items_created_at
                ON items(created_at DESC)
            """)

            conn.commit()
            cursor.close()

            logger.info("Database tables created/verified successfully")

        except Exception as e:
            logger.error(f"Failed to create tables: {e}")
            if conn:
                conn.rollback()
            raise
        finally:
            if conn:
                self.return_connection(conn)

    def get_connection(self):
        """Get a connection from the pool"""
        if not self.pool:
            raise Exception("Database pool not initialized")
        return self.pool.getconn()

    def return_connection(self, conn):
        """Return a connection to the pool"""
        if self.pool:
            self.pool.putconn(conn)

    def close_all(self):
        """Close all connections in the pool"""
        if self.pool:
            self.pool.closeall()
            logger.info("Database pool closed")

db_pool = DatabasePool()

# =============================================================================
# Flask Application
# =============================================================================

app = Flask(__name__)
app.config.from_object(Config)

# Metrics tracking
request_count = 0
error_count = 0

# =============================================================================
# Application Initialization
# =============================================================================

def _initialize_database():
    """Initialize database pool on application startup"""
    try:
        logger.info("Initializing database connection pool...")
        db_pool.initialize()
        logger.info("Database pool initialized successfully")
    except Exception as e:
        logger.warning(f"Database initialization failed (application will continue): {e}")

# Initialize database when module is loaded (for gunicorn)
_initialize_database()

# =============================================================================
# Middleware & Request Handlers
# =============================================================================

@app.before_request
def before_request():
    """Execute before each request"""
    request.start_time = datetime.utcnow()
    request.request_id = request.headers.get('X-Request-ID',
                                             f"{Config.INSTANCE_ID}-{datetime.utcnow().timestamp()}")

@app.after_request
def after_request(response):
    """Execute after each request"""
    global request_count
    request_count += 1

    # Calculate request duration
    if hasattr(request, 'start_time'):
        duration = (datetime.utcnow() - request.start_time).total_seconds() * 1000
        response.headers['X-Response-Time'] = f"{duration:.2f}ms"

    # Add request ID to response
    if hasattr(request, 'request_id'):
        response.headers['X-Request-ID'] = request.request_id

    # Add instance info
    response.headers['X-Instance-ID'] = Config.INSTANCE_ID

    # Log request
    logger.info(
        f"{request.method} {request.path} {response.status_code}",
        extra={
            'request_id': getattr(request, 'request_id', 'unknown'),
            'method': request.method,
            'path': request.path,
            'status': response.status_code,
            'duration_ms': duration if hasattr(request, 'start_time') else 0
        }
    )

    return response

@app.errorhandler(Exception)
def handle_exception(e):
    """Global exception handler"""
    global error_count
    error_count += 1

    # Log the error
    logger.error(
        f"Unhandled exception: {str(e)}",
        exc_info=True,
        extra={'request_id': getattr(request, 'request_id', 'unknown')}
    )

    # HTTP exceptions
    if isinstance(e, HTTPException):
        return jsonify({
            'error': e.name,
            'message': e.description,
            'status': e.code
        }), e.code

    # Generic errors
    return jsonify({
        'error': 'Internal Server Error',
        'message': 'An unexpected error occurred',
        'status': 500
    }), 500

# =============================================================================
# Routes
# =============================================================================

@app.route('/')
def index():
    """Root endpoint - basic health check"""
    return jsonify({
        'status': 'healthy',
        'service': 'demo-flask-app',
        'version': Config.APP_VERSION,
        'environment': Config.ENVIRONMENT,
        'hostname': socket.gethostname(),
        'instance_id': Config.INSTANCE_ID,
        'instance_ip': Config.INSTANCE_IP,
        'availability_zone': Config.AVAILABILITY_ZONE,
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    })

@app.route('/health')
def health():
    """Detailed health check endpoint"""
    health_status = {
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'version': Config.APP_VERSION,
        'checks': {
            'application': 'ok',
            'database': 'unknown'
        },
        'instance': {
            'id': Config.INSTANCE_ID,
            'ip': Config.INSTANCE_IP,
            'az': Config.AVAILABILITY_ZONE
        }
    }

    # Check database connection (non-blocking)
    try:
        if db_pool.pool:
            conn = db_pool.get_connection()
            cursor = conn.cursor()
            cursor.execute('SELECT 1')
            cursor.fetchone()
            cursor.close()
            db_pool.return_connection(conn)
            health_status['checks']['database'] = 'ok'
        else:
            health_status['checks']['database'] = 'not_initialized'
            # Application is still healthy, just database not connected yet
    except Exception as e:
        health_status['checks']['database'] = f'error: {str(e)}'
        logger.warning(f"Health check database error: {e}")

    # Return 200 even if database is not ready (app itself is healthy)
    # Use /db endpoint for strict database health check
    return jsonify(health_status), 200

@app.route('/db')
def db_check():
    """Database connectivity check"""
    try:
        if not db_pool.pool:
            return jsonify({
                'status': 'error',
                'message': 'Database pool not initialized'
            }), 503

        conn = db_pool.get_connection()
        cursor = conn.cursor()

        # Get database version
        cursor.execute('SELECT version()')
        db_version = cursor.fetchone()[0]

        # Get table count
        cursor.execute("""
            SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = 'public'
        """)
        table_count = cursor.fetchone()[0]

        # Get items count
        cursor.execute('SELECT COUNT(*) FROM items')
        items_count = cursor.fetchone()[0]

        cursor.close()
        db_pool.return_connection(conn)

        return jsonify({
            'status': 'connected',
            'database_version': db_version.split('\n')[0],
            'tables_count': table_count,
            'items_count': items_count,
            'pool_size': Config.DB_POOL_MAX_CONN
        })

    except Exception as e:
        logger.error(f"Database check failed: {e}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 503

@app.route('/api/items', methods=['GET'])
def get_items():
    """Get all items from database"""
    try:
        conn = db_pool.get_connection()
        cursor = conn.cursor()

        # Get query parameters
        limit = request.args.get('limit', 100, type=int)
        offset = request.args.get('offset', 0, type=int)

        cursor.execute("""
            SELECT id, name, description, value, created_at, updated_at
            FROM items
            ORDER BY created_at DESC
            LIMIT %s OFFSET %s
        """, (limit, offset))

        items = []
        for row in cursor.fetchall():
            items.append({
                'id': row[0],
                'name': row[1],
                'description': row[2],
                'value': row[3],
                'created_at': row[4].isoformat() if row[4] else None,
                'updated_at': row[5].isoformat() if row[5] else None
            })

        cursor.close()
        db_pool.return_connection(conn)

        return jsonify({
            'items': items,
            'count': len(items),
            'limit': limit,
            'offset': offset
        })

    except Exception as e:
        logger.error(f"Failed to get items: {e}")
        return jsonify({
            'error': 'Failed to retrieve items',
            'message': str(e)
        }), 500

@app.route('/api/items', methods=['POST'])
def create_item():
    """Create a new item"""
    try:
        data = request.get_json()

        if not data or 'name' not in data:
            return jsonify({
                'error': 'Bad Request',
                'message': 'Name is required'
            }), 400

        conn = db_pool.get_connection()
        cursor = conn.cursor()

        cursor.execute("""
            INSERT INTO items (name, description, value)
            VALUES (%s, %s, %s)
            RETURNING id, name, description, value, created_at
        """, (
            data['name'],
            data.get('description', ''),
            data.get('value', '')
        ))

        row = cursor.fetchone()
        item = {
            'id': row[0],
            'name': row[1],
            'description': row[2],
            'value': row[3],
            'created_at': row[4].isoformat() if row[4] else None
        }

        conn.commit()
        cursor.close()
        db_pool.return_connection(conn)

        logger.info(f"Created item: {item['id']}")

        return jsonify({
            'message': 'Item created successfully',
            'item': item
        }), 201

    except Exception as e:
        logger.error(f"Failed to create item: {e}")
        return jsonify({
            'error': 'Failed to create item',
            'message': str(e)
        }), 500

@app.route('/metrics')
def metrics():
    """Prometheus-style metrics endpoint"""
    metrics_data = [
        '# HELP application_info Application information',
        '# TYPE application_info gauge',
        f'application_info{{version="{Config.APP_VERSION}",environment="{Config.ENVIRONMENT}",instance="{Config.INSTANCE_ID}"}} 1',
        '',
        '# HELP application_up Application is running',
        '# TYPE application_up gauge',
        'application_up 1',
        '',
        '# HELP http_requests_total Total HTTP requests',
        '# TYPE http_requests_total counter',
        f'http_requests_total {request_count}',
        '',
        '# HELP http_errors_total Total HTTP errors',
        '# TYPE http_errors_total counter',
        f'http_errors_total {error_count}',
    ]

    # Database connection pool metrics
    if db_pool.pool:
        metrics_data.extend([
            '',
            '# HELP db_pool_size Database connection pool size',
            '# TYPE db_pool_size gauge',
            f'db_pool_size {Config.DB_POOL_MAX_CONN}',
        ])

    return Response('\n'.join(metrics_data), mimetype='text/plain')

# =============================================================================
# Application Lifecycle
# =============================================================================

def initialize_app():
    """Initialize application on startup"""
    logger.info("=" * 60)
    logger.info("Starting Flask Application")
    logger.info(f"Version: {Config.APP_VERSION}")
    logger.info(f"Environment: {Config.ENVIRONMENT}")
    logger.info(f"Instance ID: {Config.INSTANCE_ID}")
    logger.info(f"Instance IP: {Config.INSTANCE_IP}")
    logger.info(f"Availability Zone: {Config.AVAILABILITY_ZONE}")
    logger.info("=" * 60)

    # Initialize database pool
    try:
        db_pool.initialize()
    except Exception as e:
        logger.warning(f"Database initialization failed (application will continue): {e}")

def shutdown_app(signum=None, frame=None):
    """Graceful shutdown"""
    logger.info("Shutting down application...")
    db_pool.close_all()
    logger.info("Application shutdown complete")
    sys.exit(0)

# Register signal handlers for graceful shutdown
signal.signal(signal.SIGTERM, shutdown_app)
signal.signal(signal.SIGINT, shutdown_app)

# =============================================================================
# Main Entry Point
# =============================================================================

if __name__ == '__main__':
    initialize_app()

    app.run(
        host='0.0.0.0',
        port=Config.APPLICATION_PORT,
        debug=Config.DEBUG,
        threaded=True
    )
