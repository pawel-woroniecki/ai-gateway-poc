# ============================================================================
# AI Gateway PoC – tworzenie projektu GCP
#
# Tworzy projekt z suffixem podanym jako zmienna (generowanym przez skrypt
# create-project.sh). Dzięki unikalnemu suffixowi można usunąć projekt
# i natychmiast stworzyć nowy (bez czekania na 30 dni w GCP).
#
# Uruchomienie: ./scripts/create-project.sh
#
# State w centralnym buckecie GCS: reinventor-terraform-states
# Prefix: ai-gateway-poc-{suffix}/project
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
    # bucket i prefix ustawiane przez -backend-config w create-project.sh
  }
}

locals {
  project_id = "${var.project_name_base}-${var.suffix}"
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
