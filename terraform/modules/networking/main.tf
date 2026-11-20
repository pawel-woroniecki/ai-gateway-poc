# ============================================================================
# Moduł: networking
# VPC, subnet, firewall rules, opcjonalnie Cloud NAT
# ============================================================================

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "network_name" {
  type    = string
  default = "ai-gateway-vpc"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "Secondary range dla GKE pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range dla GKE services"
  type        = string
  default     = "10.2.0.0/20"
}

variable "enable_cloud_nat" {
  description = "Włącz Cloud NAT dla egress z prywatnych node'ów"
  type        = bool
  default     = true
}

# --- VPC ---

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# --- Subnet ---

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.network_name}-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true
}

# --- Firewall rules ---

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.network_name}-allow-internal"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr,
    var.pods_cidr,
    var.services_cidr,
  ]

  description = "Ruch wewnętrzny w klastrze"
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.network_name}-allow-health-checks"
  project = var.project_id
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }

  # GCP health check ranges
  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]

  description = "Health checks z GCP load balancerów"
}

# --- Cloud NAT (opcjonalny, ale rekomendowany dla prywatnych node'ów) ---

resource "google_compute_router" "router" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = "${var.network_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count                              = var.enable_cloud_nat ? 1 : 0
  name                               = "${var.network_name}-nat"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.router[0].name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- Outputs ---

output "network_id" {
  value = google_compute_network.vpc.id
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "subnet_id" {
  value = google_compute_subnetwork.subnet.id
}

output "subnet_name" {
  value = google_compute_subnetwork.subnet.name
}
