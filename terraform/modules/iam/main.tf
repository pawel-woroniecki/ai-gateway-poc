# ============================================================================
# Moduł: iam
# Service accounts i Workload Identity dla komponentów w klastrze
# ============================================================================

variable "project_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "k8s_namespace" {
  type    = string
  default = "default"
}

# --- SA dla LiteLLM (dostęp do Vertex AI) ---

resource "google_service_account" "litellm" {
  account_id   = "ai-gateway-litellm"
  display_name = "AI Gateway – LiteLLM"
  project      = var.project_id
}

resource "google_project_iam_member" "litellm_vertex" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.litellm.email}"
}

# Workload Identity binding: K8s SA → GCP SA
resource "google_service_account_iam_member" "litellm_wi" {
  service_account_id = google_service_account.litellm.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/litellm]"
}

# --- SA dla PCA (opcjonalnie – jeśli potrzebuje dostępu do GCP) ---

resource "google_service_account" "pca" {
  account_id   = "ai-gateway-pca"
  display_name = "AI Gateway – PCA"
  project      = var.project_id
}

resource "google_service_account_iam_member" "pca_wi" {
  service_account_id = google_service_account.pca.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/pca]"
}

# --- Outputs ---

output "litellm_sa_email" {
  value       = google_service_account.litellm.email
  description = "GCP SA dla LiteLLM – do adnotacji w K8s ServiceAccount"
}

output "pca_sa_email" {
  value       = google_service_account.pca.email
  description = "GCP SA dla PCA"
}
