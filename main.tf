# main.tf variables
variable "aws_region" {
  description = "The AWS region to deploy to (e.g. us-east-1)"
  type        = string
}

variable "project_name" {
  description = "Name of the project. It will be used for naming resources"
  type        = string
  default     = "wireguard"
}

variable "scripts_dir" {
  description = "Directory containing various scripts. Used mostly by GHA runner."
  type        = string
  default     = "./"
}

# main.tf resources
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      version = "> 4.11.0"
      source  = "hashicorp/aws"
    }
    random = {
      version = "> 3.5.0"
      source  = "hashicorp/random"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      project     = var.project_name
      provisioner = "terraform"
    }
  }
}
