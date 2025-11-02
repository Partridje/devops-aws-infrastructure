# Scripts Documentation

## setup-terraform-backend.sh

**Purpose**: Creates S3 bucket and DynamoDB table for Terraform remote state management.

### Features

✅ **Idempotent** - Safe to run multiple times  
✅ **Auto-saves configuration** - Remembers bucket name  
✅ **Account-specific naming** - Uses AWS Account ID  
✅ **Security best practices** - Encryption, versioning, public access block  

### Usage

#### First Run (Creates Backend)

```bash
./scripts/setup-terraform-backend.sh
```

**What happens**:
1. Checks AWS credentials
2. Creates bucket: `terraform-state-demo-flask-app-<ACCOUNT_ID>`
3. Creates DynamoDB table: `terraform-state-lock-demo-flask-app`
4. Enables encryption, versioning, public access block
5. Saves configuration to `.terraform-backend-config`

**Output**:
```
✅ S3 bucket: terraform-state-demo-flask-app-123456789012
✅ DynamoDB table: terraform-state-lock-demo-flask-app
✅ Configuration saved to .terraform-backend-config
```

#### Subsequent Runs (Reuses Backend)

```bash
./scripts/setup-terraform-backend.sh
```

**What happens**:
1. Finds existing `.terraform-backend-config`
2. Asks: "Continue with this configuration? (y/n)"
3. If yes: Uses existing bucket and updates settings
4. If no: Exits (delete `.terraform-backend-config` to create new backend)

### Custom Configuration

#### Specify Region and Bucket Name

```bash
./scripts/setup-terraform-backend.sh <region> <bucket-name>
```

**Example**:
```bash
./scripts/setup-terraform-backend.sh us-west-2 my-custom-terraform-state
```

### Troubleshooting

#### "Bucket already exists" Error

The script checks if bucket exists before creating. If you see this error:
- Another AWS account owns a bucket with this name
- Change the bucket name by deleting `.terraform-backend-config` and re-running

#### Reset Configuration

```bash
# Delete saved configuration
rm .terraform-backend-config

# Run script again to create new backend
./scripts/setup-terraform-backend.sh
```

#### Verify Backend Exists

```bash
# Check S3 bucket
aws s3 ls | grep terraform-state

# Check DynamoDB table
aws dynamodb list-tables | grep terraform-state-lock
```

### Security Features

1. **Encryption at Rest**: AES256 encryption enabled
2. **Encryption in Transit**: TLS-only bucket policy
3. **Versioning**: Enabled for state file history
4. **Public Access**: Blocked at all levels
5. **DynamoDB Backups**: Point-in-Time Recovery enabled

### Resources Created

| Resource | Name Pattern | Purpose |
|----------|-------------|---------|
| S3 Bucket | `terraform-state-demo-flask-app-<ACCOUNT_ID>` | Store Terraform state files |
| DynamoDB Table | `terraform-state-lock-demo-flask-app` | State locking |
| Config File | `.terraform-backend-config` | Remember settings (gitignored) |

### Cost

**Minimal costs**:
- S3: ~$0.01/month for state storage
- DynamoDB: Pay-per-request (usually free tier)
- Total: ~$0.05/month

---

## setup-github-oidc.sh

**Purpose**: Configures GitHub Actions OIDC authentication with AWS.

### Usage

```bash
./scripts/setup-github-oidc.sh <github-org> <github-repo>
```

**Example**:
```bash
./scripts/setup-github-oidc.sh myusername devops-aws-infrastructure
```

See `DEPLOYMENT_GUIDE.md` for complete GitHub Actions setup.

---

## generate-cert.sh

**Purpose**: Generates self-signed SSL certificates for local testing.

### Usage

```bash
./scripts/generate-cert.sh
```

**Note**: Only needed for testing HTTPS locally. AWS deployment uses ALB with AWS Certificate Manager.
