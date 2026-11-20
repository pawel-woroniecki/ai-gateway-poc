# ============================================================================
# Zmienne dla środowiska dev
# ============================================================================

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "europe-central2"
}

variable "zone" {
  description = "GCP Zone (zonalny klaster = darmowy control plane)"
  type        = string
  default     = "europe-central2-a"
}

variable "network_name" {
  description = "Nazwa VPC"
  type        = string
  default     = "ai-gateway-vpc"
}

variable "cluster_name" {
  description = "Nazwa klastra GKE"
  type        = string
  default     = "ai-gateway-cluster"
}

variable "machine_type" {
  description = "Typ maszyny dla node pool"
  type        = string
  default     = "e2-standard-2"
}

variable "node_count" {
  description = "Liczba node'ów w pool"
  type        = number
  default     = 1
}

variable "state_bucket" {
  description = "Nazwa bucketa GCS dla Terraform state (z bootstrap)"
  type        = string
}

variable "terraform_sa_email" {
  description = "Email SA Terraform (z bootstrap)"
  type        = string
  default     = ""
}
