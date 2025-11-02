terraform {
  backend "s3" {
    bucket         = "terraform-state-demo-flask-app-eu-851725636341"
    key            = "prod/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-state-lock-demo-flask-app"
    encrypt        = true
  }
}
