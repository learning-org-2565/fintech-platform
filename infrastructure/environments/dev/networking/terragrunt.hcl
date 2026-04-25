include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/networking"
}

inputs = {
  project_id  = "fintech-platform-lab"
  region      = "asia-south1"
  environment = "dev"

  # Dev gets smaller CIDR ranges — we don't need 262K pod IPs for learning
  # But we keep the structure identical to prod
  subnet_cidr   = "10.0.0.0/20"
  pods_cidr     = "10.4.0.0/14"
  services_cidr = "10.8.0.0/20"
}