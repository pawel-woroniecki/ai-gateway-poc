# ============================================================================
# Outputs – projekt GCP
# ============================================================================

output "project_id" {
  value       = google_project.poc.project_id
  description = "Wygenerowany project_id (z suffixem) – użyj w bootstrap i environments/dev"
}

output "project_number" {
  value       = google_project.poc.number
  description = "Numer projektu GCP"
}

output "project_name" {
  value       = google_project.poc.name
  description = "Nazwa projektu"
}

output "suffix" {
  value       = var.suffix
  description = "Suffix projektu"
}
