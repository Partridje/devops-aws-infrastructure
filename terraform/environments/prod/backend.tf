terraform {
  backend "s3" {
    bucket         = "YOUR-TERRAFORM-STATE-BUCKET" # Update after running setup-terraform-backend.sh
    key            = "prod/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-state-lock-demo-flask-app"
    encrypt        = true
  }
}
