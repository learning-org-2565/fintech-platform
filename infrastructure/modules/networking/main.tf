# VPC and Subnets
# Why a custom VPC? The default VPC has overly permissive firewall rules.
# In fintech, the default VPC is a security audit failure.

resource "google_compute_network" "main" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false  # We control subnets explicitly
  project                 = var.project_id
}

# GKE subnet with secondary ranges for pods and services
resource "google_compute_subnetwork" "gke" {
  name          = "${var.environment}-gke-subnet"
  ip_cidr_range = var.subnet_cidr        # Node IPs
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.project_id

  # Secondary ranges for GKE pods and services
  # Why secondary ranges? GKE uses VPC-native networking.
  # Pods get IPs from a separate range, not the node range.
  # This means pods are directly routable in the VPC — needed for
  # service mesh, network policies, and basically everything enterprise.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # Enable private Google access — pods can reach Google APIs
  # without a public IP. Security requirement for fintech.
  private_ip_google_access = true
}

# Cloud NAT — gives private nodes outbound internet access
# without public IPs. Required for pulling container images.
resource "google_compute_router" "router" {
  name    = "${var.environment}-router"
  region  = var.region
  network = google_compute_network.main.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.environment}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Logging — you want to see NAT traffic for debugging and auditing
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}