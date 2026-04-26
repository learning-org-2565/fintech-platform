locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/networking"
}

inputs = {
  project_id  = local.env.locals.project_id
  region      = local.env.locals.region
  environment = local.env.locals.environment

  subnet_cidr   = "10.0.0.0/20"
  pods_cidr     = "10.4.0.0/14"
  services_cidr = "10.8.0.0/20"
}
