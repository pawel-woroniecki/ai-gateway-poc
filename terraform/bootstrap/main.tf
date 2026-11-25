# ============================================================================
# AI Gateway PoC – Bootstrap
# Tworzy zasoby wymagane PRZED pierwszym `terraform apply` w environments/dev:
#   - Service account dla Terraform
#   - Włączenie wymaganych API
#
# State w centralnym buckecie GCS: reinventor-terraform-states
# Prefix: ai-gateway-poc-{suffix}/bootstrap
#
# Uruchomienie: ./scripts/bootstrap.sh
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
    # bucket i prefix ustawiane przez -backend-config w bootstrap.sh
  }
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-central2"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- API do włączenia ---

resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# --- Service Account dla Terraform / GKE ---

resource "google_service_account" "terraform" {
  account_id   = "ai-gateway-terraform"
  display_name = "AI Gateway – Terraform SA"
  project      = var.project_id

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

resource "google_project_iam_member" "terraform_roles" {
  for_each = toset([
    "roles/container.admin",
    "roles/compute.networkAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
    "roles/aiplatform.user",
    "roles/serviceusage.serviceUsageAdmin",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# --- Outputs ---

output "terraform_sa_email" {
  value       = google_service_account.terraform.email
  description = "Email service account Terraform"
}
