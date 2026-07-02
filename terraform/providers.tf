terraform {
  required_version = ">= 1.11"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }

  backend "s3" {
    bucket                      = "tf-state-slz"
    key                         = "landing-zone/prod.tfstate"
    region                      = "eu-west-3"
    encrypt                     = true
    use_lockfile                = true
    skip_credentials_validation = true
  }
}

provider "aws" {
  region = var.aws_region
}

provider "azurerm" {
  features {}
}
