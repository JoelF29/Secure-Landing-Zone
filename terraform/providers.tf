# Backend distant CHIFFRÉ et verrouillé — jamais de state local en clair.
# TODO: renseigne ton bucket/storage account de state (créé hors de ce repo).
terraform {
  required_version = ">= 1.7"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }

  # backend "s3" {
  #   bucket         = "my-tfstate-encrypted"
  #   key            = "landing-zone/prod.tfstate"
  #   region         = "eu-west-3"
  #   encrypt        = true            # chiffrement du state
  #   dynamodb_table = "tfstate-lock"  # verrouillage concurrent
  # }
}

provider "aws" {
  region = var.aws_region
}

provider "azurerm" {
  features {}
}
