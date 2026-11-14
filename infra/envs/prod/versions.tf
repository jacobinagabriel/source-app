terraform {
  # Ephemeral resources and write-only arguments keep the app password out of state.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.0"
    }
  }

  backend "s3" {
    bucket       = "gabriel-jacobina-terraform-state"
    key          = "source-app/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "cdc-bench"
      Repo      = "source-app"
      Env       = "prod"
      terraform = "true"
    }
  }
}
