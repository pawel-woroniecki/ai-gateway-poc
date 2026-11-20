# ============================================================================
# Moduł: gke
# GKE Standard cluster – zonalny, 1 node pool
# Darmowy control plane dla jednego klastra zonalnego
# ============================================================================

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "cluster_name" {
  type    = string
  default = "ai-gateway-cluster"
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "disk_size_gb" {
  type    = number
  default = 50
}

variable "terraform_sa_email" {
  description = "Email SA Terraform – do Workload Identity binding"
  type        = string
  default     = ""
}

# --- GKE Cluster ---

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.zone # zonalny = darmowy control plane

  # Usuwamy domyślny node pool, tworzymy własny
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_id
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Logging i monitoring – podstawowe (darmowe)
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false # Oszczędność – włączymy w razie potrzeby
    }
  }

  # Release channel – stable dla przewidywalności
  release_channel {
    channel = "STABLE"
  }

  deletion_protection = false # PoC – potrzebujemy łatwego terraform destroy
}

# --- Node Pool ---

resource "google_container_node_pool" "primary_nodes" {
  name     = "${var.cluster_name}-pool"
  project  = var.project_id
  location = var.zone
  cluster  = google_container_cluster.primary.name

  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      environment = "poc"
      project     = "ai-gateway"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# --- Outputs ---

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.primary.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "cluster_location" {
  value = google_container_cluster.primary.location
}
