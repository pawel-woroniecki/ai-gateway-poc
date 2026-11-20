# ============================================================================
# AI Gateway PoC – Bootstrap
# Tworzy zasoby wymagane PRZED pierwszym `terraform init` w environments/dev:
#   - GCS bucket na Terraform state
#   - Service account dla Terraform
#   - Włączenie wymaganych API
#
# Uruchamiany raz, ręcznie: cd bootstrap && terraform init && terraform apply
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Bootstrap trzyma state lokalnie – jedyny wyjątek od reguły GCS backend
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

variable "state_bucket_name" {
  description = "Nazwa bucketu GCS na Terraform state"
  type        = string
  default     = ""
}

locals {
  state_bucket = var.state_bucket_name != "" ? var.state_bucket_name : "${var.project_id}-tf-state"
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
    "iam.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# --- GCS bucket na Terraform state ---

resource "google_storage_bucket" "tf_state" {
  name     = local.state_bucket
  location = var.region
  project  = var.project_id

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    purpose = "terraform-state"
    project = "ai-gateway-poc"
  }

  depends_on = [google_project_service.apis["cloudresourcemanager.googleapis.com"]]
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

output "state_bucket" {
  value       = google_storage_bucket.tf_state.name
  description = "Nazwa bucketu GCS – użyj w backend {} environments/dev"
}

output "terraform_sa_email" {
  value       = google_service_account.terraform.email
  description = "Email service account Terraform"
}
