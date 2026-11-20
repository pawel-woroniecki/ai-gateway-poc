# ============================================================================
# Outputs – środowisko dev
# ============================================================================

output "network_name" {
  value = module.networking.network_name
}

output "subnet_name" {
  value = module.networking.subnet_name
}

output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "cluster_location" {
  value = module.gke.cluster_location
}

output "litellm_sa_email" {
  value       = module.iam.litellm_sa_email
  description = "Adnotuj K8s SA litellm tym emailem dla Workload Identity"
}

output "pca_sa_email" {
  value       = module.iam.pca_sa_email
  description = "Adnotuj K8s SA pca tym emailem dla Workload Identity"
}
