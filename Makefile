.PHONY: help init plan apply destroy validate fmt clean test lint setup-backend

# Default environment
ENV ?= dev
REGION ?= eu-north-1

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Terraform directories
TERRAFORM_DIR := terraform/environments/$(ENV)
MODULES_DIR := terraform/modules

help: ## Show this help message
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'

init: ## Initialize Terraform
	@echo "$(GREEN)Initializing Terraform for $(ENV) environment...$(NC)"
	cd $(TERRAFORM_DIR) && terraform init -upgrade

plan: ## Run terraform plan
	@echo "$(GREEN)Planning infrastructure changes for $(ENV)...$(NC)"
	cd $(TERRAFORM_DIR) && terraform plan -out=tfplan

apply: ## Apply terraform changes
	@if [ "$(ENV)" = "prod" ]; then \
		echo "$(RED)❌ ERROR: Production deployments must go through CI/CD!$(NC)"; \
		echo "$(YELLOW)Use GitHub Actions → Terraform Apply workflow instead$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Applying infrastructure changes for $(ENV)...$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd $(TERRAFORM_DIR) && terraform apply tfplan; \
		rm -f $(TERRAFORM_DIR)/tfplan; \
	else \
		echo "$(RED)Cancelled$(NC)"; \
	fi

apply-auto: ## Apply terraform changes without confirmation (CI/CD)
	@echo "$(YELLOW)Auto-applying infrastructure changes for $(ENV)...$(NC)"
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve

destroy: ## Destroy infrastructure
	@if [ "$(ENV)" = "prod" ]; then \
		echo "$(RED)❌ ERROR: Production destruction must go through CI/CD!$(NC)"; \
		echo "$(YELLOW)Use GitHub Actions → Terraform Destroy workflow instead$(NC)"; \
		exit 1; \
	fi
	@echo "$(RED)Destroying infrastructure for $(ENV)...$(NC)"
	@read -p "Are you ABSOLUTELY sure? Type '$(ENV)' to confirm: " -r; \
	echo; \
	if [[ $$REPLY == "$(ENV)" ]]; then \
		cd $(TERRAFORM_DIR) && terraform destroy; \
	else \
		echo "$(RED)Cancelled - confirmation did not match$(NC)"; \
	fi

validate: ## Validate Terraform configuration
	@echo "$(GREEN)Validating Terraform configuration...$(NC)"
	@cd terraform && terraform fmt -check -recursive || (echo "$(RED)Format check failed!$(NC)" && exit 1)
	@cd $(TERRAFORM_DIR) && terraform validate

fmt: ## Format Terraform files
	@echo "$(GREEN)Formatting Terraform files...$(NC)"
	terraform fmt -recursive terraform/

output: ## Show terraform outputs
	@cd $(TERRAFORM_DIR) && terraform output

output-json: ## Show terraform outputs in JSON
	@cd $(TERRAFORM_DIR) && terraform output -json

refresh: ## Refresh terraform state
	@echo "$(GREEN)Refreshing Terraform state for $(ENV)...$(NC)"
	cd $(TERRAFORM_DIR) && terraform refresh

state-list: ## List resources in state
	@cd $(TERRAFORM_DIR) && terraform state list

clean: ## Clean temporary files
	@echo "$(GREEN)Cleaning temporary files...$(NC)"
	find terraform -type f -name "tfplan" -delete
	find terraform -type f -name "*.tfstate.backup" -delete
	find terraform -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.log" -delete

test: lint validate ## Run all tests

lint: ## Run linting tools
	@echo "$(GREEN)Running linters...$(NC)"
	@command -v tflint >/dev/null 2>&1 && (cd terraform && tflint --recursive) || echo "$(YELLOW)tflint not installed, skipping$(NC)"
	@command -v tfsec >/dev/null 2>&1 && tfsec terraform/ || echo "$(YELLOW)tfsec not installed, skipping$(NC)"
	@command -v checkov >/dev/null 2>&1 && checkov -d terraform/ --quiet || echo "$(YELLOW)checkov not installed, skipping$(NC)"

cost: ## Estimate infrastructure cost (requires infracost)
	@echo "$(GREEN)Estimating infrastructure cost for $(ENV)...$(NC)"
	@command -v infracost >/dev/null 2>&1 || (echo "$(RED)infracost not installed$(NC)" && exit 1)
	cd $(TERRAFORM_DIR) && infracost breakdown --path .

setup-backend: ## Setup Terraform remote backend (S3 + DynamoDB)
	@echo "$(GREEN)Setting up Terraform backend...$(NC)"
	@bash scripts/setup-terraform-backend.sh $(REGION)

app-build: ## Build application Docker image
	@echo "$(GREEN)Building application Docker image...$(NC)"
	cd app && docker build -t demo-flask-app:latest .

app-run: ## Run application locally
	@echo "$(GREEN)Starting application locally...$(NC)"
	cd app && docker-compose up -d
	@echo "$(GREEN)Application available at http://localhost:5001$(NC)"

app-stop: ## Stop local application
	@echo "$(YELLOW)Stopping application...$(NC)"
	cd app && docker-compose down

app-logs: ## View application logs
	@cd app && docker-compose logs -f app

app-test: ## Test application endpoints
	@echo "$(GREEN)Testing application endpoints...$(NC)"
	@curl -s http://localhost:5001/ | jq . || echo "Health check endpoint"
	@curl -s http://localhost:5001/health | jq . || echo "Health endpoint"
	@curl -s http://localhost:5001/metrics || echo "Metrics endpoint"

install-tools: ## Install required tools (macOS)
	@echo "$(GREEN)Installing required tools...$(NC)"
	@command -v brew >/dev/null 2>&1 || (echo "$(RED)Homebrew not installed$(NC)" && exit 1)
	brew install terraform tflint tfsec awscli jq pre-commit
	pip3 install checkov

install-pre-commit: ## Install pre-commit hooks
	@echo "$(GREEN)Installing pre-commit hooks...$(NC)"
	pre-commit install
	pre-commit install --hook-type commit-msg

docs: ## Generate documentation
	@echo "$(GREEN)Generating documentation...$(NC)"
	@cd terraform/modules/vpc && terraform-docs markdown . > README.md
	@cd terraform/modules/security && terraform-docs markdown . > README.md
	@cd terraform/modules/ec2 && terraform-docs markdown . > README.md
	@cd terraform/modules/rds && terraform-docs markdown . > README.md
	@cd terraform/modules/monitoring && terraform-docs markdown . > README.md
	@echo "$(GREEN)Documentation generated!$(NC)"

graph: ## Generate Terraform dependency graph
	@echo "$(GREEN)Generating dependency graph...$(NC)"
	cd $(TERRAFORM_DIR) && terraform graph | dot -Tpng > graph.png
	@echo "$(GREEN)Graph saved to $(TERRAFORM_DIR)/graph.png$(NC)"

unlock: ## Unlock Terraform state (requires LOCK_ID)
	@test -n "$(LOCK_ID)" || (echo "$(RED)LOCK_ID is required. Usage: make unlock LOCK_ID=xxx$(NC)" && exit 1)
	@echo "$(YELLOW)Unlocking state with ID: $(LOCK_ID)$(NC)"
	cd $(TERRAFORM_DIR) && terraform force-unlock -force $(LOCK_ID)

import: ## Import existing resource (requires RESOURCE and ID)
	@test -n "$(RESOURCE)" || (echo "$(RED)RESOURCE is required$(NC)" && exit 1)
	@test -n "$(ID)" || (echo "$(RED)ID is required$(NC)" && exit 1)
	@echo "$(GREEN)Importing resource $(RESOURCE) with ID $(ID)$(NC)"
	cd $(TERRAFORM_DIR) && terraform import $(RESOURCE) $(ID)

workspace-list: ## List Terraform workspaces
	@cd $(TERRAFORM_DIR) && terraform workspace list

workspace-select: ## Select Terraform workspace (requires WORKSPACE)
	@test -n "$(WORKSPACE)" || (echo "$(RED)WORKSPACE is required$(NC)" && exit 1)
	@cd $(TERRAFORM_DIR) && terraform workspace select $(WORKSPACE)

workspace-new: ## Create new Terraform workspace (requires WORKSPACE)
	@test -n "$(WORKSPACE)" || (echo "$(RED)WORKSPACE is required$(NC)" && exit 1)
	@cd $(TERRAFORM_DIR) && terraform workspace new $(WORKSPACE)

check-aws: ## Check AWS credentials and configuration
	@echo "$(GREEN)Checking AWS configuration...$(NC)"
	@aws sts get-caller-identity && echo "$(GREEN)AWS credentials valid!$(NC)" || echo "$(RED)AWS credentials invalid!$(NC)"

ssh-instance: ## Connect to EC2 instance via SSM (requires INSTANCE_ID)
	@test -n "$(INSTANCE_ID)" || (echo "$(RED)INSTANCE_ID is required$(NC)" && exit 1)
	@echo "$(GREEN)Connecting to instance $(INSTANCE_ID)...$(NC)"
	aws ssm start-session --target $(INSTANCE_ID)

logs: ## Tail CloudWatch logs (requires LOG_GROUP)
	@test -n "$(LOG_GROUP)" || (echo "$(RED)LOG_GROUP is required. Example: make logs LOG_GROUP=/aws/ec2/application$(NC)" && exit 1)
	@echo "$(GREEN)Tailing logs from $(LOG_GROUP)...$(NC)"
	aws logs tail $(LOG_GROUP) --follow

alb-url: ## Get ALB URL
	@cd $(TERRAFORM_DIR) && terraform output -raw alb_dns_name 2>/dev/null || echo "$(RED)ALB not deployed yet$(NC)"

db-secret: ## Get database credentials from Secrets Manager
	@SECRET_ARN=$$(cd $(TERRAFORM_DIR) && terraform output -raw db_secret_arn 2>/dev/null); \
	test -n "$$SECRET_ARN" || (echo "$(RED)Database secret not found$(NC)" && exit 1); \
	aws secretsmanager get-secret-value --secret-id $$SECRET_ARN --query SecretString --output text | jq .

health-check: ## Check application health
	@ALB_URL=$$(cd $(TERRAFORM_DIR) && terraform output -raw alb_dns_name 2>/dev/null); \
	test -n "$$ALB_URL" || (echo "$(RED)ALB not deployed yet$(NC)" && exit 1); \
	echo "$(GREEN)Checking health of http://$$ALB_URL/health$(NC)"; \
	curl -s "http://$$ALB_URL/health" | jq . || curl -s "http://$$ALB_URL/health"

smoke-test: ## Run smoke tests against deployed application
	@ALB_URL=$$(cd $(TERRAFORM_DIR) && terraform output -raw alb_dns_name 2>/dev/null); \
	test -n "$$ALB_URL" || (echo "$(RED)ALB not deployed yet$(NC)" && exit 1); \
	echo "$(GREEN)Running smoke tests...$(NC)"; \
	curl -f "http://$$ALB_URL/" && echo "$(GREEN)✓ Root endpoint$(NC)" || echo "$(RED)✗ Root endpoint$(NC)"; \
	curl -f "http://$$ALB_URL/health" && echo "$(GREEN)✓ Health endpoint$(NC)" || echo "$(RED)✗ Health endpoint$(NC)"; \
	curl -f "http://$$ALB_URL/db" && echo "$(GREEN)✓ Database endpoint$(NC)" || echo "$(RED)✗ Database endpoint$(NC)"

.DEFAULT_GOAL := help
