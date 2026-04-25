# Dev environment root config
# All modules in dev/ inherit these variables

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  project_id  = "fintech-platform-lab"
  region      = "asia-south1"
  environment = "dev"

  # Dev-specific: keep everything small and cheap
  # These values get passed to modules as variables
}