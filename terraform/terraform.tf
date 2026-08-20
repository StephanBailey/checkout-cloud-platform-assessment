terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket       = "checkout-cloud-platform-assessment-tfstate" # TODO: replace with real bucket
    key          = "checkout-api/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true

    workspace_key_prefix = "env"
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Project     = local.project_name
      ManagedBy   = "terraform"
      Environment = terraform.workspace
    }
  }
}

check "workspace_is_valid" {
  assert {
    condition     = contains(["dev", "nonprod", "prod"], terraform.workspace)
    error_message = "terraform.workspace is '${terraform.workspace}' - select dev, nonprod, or prod (e.g. via 'task tf:plan ENV=dev') before running this configuration."
  }
}
