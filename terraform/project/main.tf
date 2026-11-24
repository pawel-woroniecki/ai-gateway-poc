# ============================================================================
# AI Gateway PoC – tworzenie projektu GCP
#
# Generuje unikalny project_id z losowym 4-literowym suffixem, dzięki czemu
# można usunąć projekt i natychmiast stworzyć nowy (bez czekania na
# permanentne usunięcie starego w GCP – 30 dni).
#
# Uruchomienie: ./scripts/create-project.sh
#
# State w centralnym buckecie GCS: reinventor-terraform-states
# Prefix: ai-gateway-poc/project (stały – suffix jeszcze nie istnieje)
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "gcs" {
    # bucket i prefix ustawiane przez -backend-config w create-project.sh
    # Prefix stały: ai-gateway-poc/project (suffix jeszcze nie istnieje)
  }
}

# --- Losowy suffix ---

resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = false
  special = false

  # Wymuszenie nowego suffixu po ręcznym usunięciu projektu
  keepers = {
    base_name = var.project_name_base
  }
}

locals {
  project_id = "${var.project_name_base}-${random_string.suffix.result}"
}

# --- Projekt GCP ---

resource "google_project" "poc" {
  name                = local.project_id
  project_id          = local.project_id
  billing_account     = var.billing_account
  org_id              = var.org_id != "" ? var.org_id : null
  folder_id           = var.folder_id != "" ? var.folder_id : null
  deletion_policy     = "DELETE"

  labels = {
    purpose     = "ai-gateway-poc"
    environment = "dev"
    managed-by  = "terraform"
  }
}

# --- Włączenie podstawowych API ---
# (pozostałe API włącza bootstrap, tu tylko te wymagane do dalszej pracy)

resource "google_project_service" "essential_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudbilling.googleapis.com",
  ])

  project            = google_project.poc.project_id
  service            = each.value
  disable_on_destroy = false
}
