variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR range for the GKE subnet (node IPs)"
  default     = "10.0.0.0/20"  # 4,094 IPs — plenty for dev
}

variable "pods_cidr" {
  type        = string
  description = "Secondary CIDR for GKE pods"
  default     = "10.4.0.0/14"  # 262,142 IPs — K8s is hungry for pod IPs
}

variable "services_cidr" {
  type        = string
  description = "Secondary CIDR for GKE services"
  default     = "10.8.0.0/20"  # 4,094 IPs — enough for services
}