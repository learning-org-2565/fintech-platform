# Root terragrunt.hcl
# This is inherited by ALL child configs. Change here = change everywhere.

# Remote state configuration
remote_state {
  backend = "gcs"
  config = {
    bucket   = "fintech-platform-lab-tf-state"
    prefix   = "${path_relative_to_include()}/terraform.tfstate"
    project  = "fintech-platform-lab"
    location = "asia-south1"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Generate provider config for all children
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}
EOF
}