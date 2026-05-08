# terraform/aws/main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Store state in S3. Create this bucket manually before running terraform init.
  backend "s3" {
    bucket = "petclinic1234-tfstate-268015775379"   # must be globally unique
    key    = "petclinic/terraform.tfstate"
    region = "us-east-1"
    # Enable state locking (prevents concurrent runs from corrupting state)
    dynamodb_table = "petclinic-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}
