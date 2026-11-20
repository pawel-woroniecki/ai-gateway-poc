# ============================================================================
# AI Gateway PoC – środowisko dev
# Root module łączący networking, GKE i IAM
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    # bucket i prefix ustawiane przez -backend-config w skrypcie up.sh
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Moduły ---

module "networking" {
  source = "../../modules/networking"

  project_id   = var.project_id
  region       = var.region
  network_name = var.network_name
}

module "gke" {
  source = "../../modules/gke"

  project_id          = var.project_id
  region              = var.region
  zone                = var.zone
  cluster_name        = var.cluster_name
  network_id          = module.networking.network_id
  subnet_id           = module.networking.subnet_id
  machine_type        = var.machine_type
  node_count          = var.node_count
  terraform_sa_email  = var.terraform_sa_email

  depends_on = [module.networking]
}

module "iam" {
  source = "../../modules/iam"

  project_id    = var.project_id
  cluster_name  = module.gke.cluster_name
  k8s_namespace = "default"

  depends_on = [module.gke]
}
