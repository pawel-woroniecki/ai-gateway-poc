# ============================================================================
# Zmienne – tworzenie projektu GCP
# ============================================================================

variable "suffix" {
  description = "4-literowy suffix projektu (generowany przez create-project.sh)"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{4}$", var.suffix))
    error_message = "Suffix musi mieć dokładnie 4 małe litery (a-z)."
  }
}

variable "project_name_base" {
  description = "Bazowa nazwa projektu (bez suffixu)."
  type        = string
  default     = "reinventor-ai-gateway-poc"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{5,25}$", var.project_name_base))
    error_message = "Nazwa bazowa: 6-26 znaków, małe litery, cyfry i myślniki, zaczynająca się od litery."
  }
}

variable "billing_account" {
  description = "ID konta rozliczeniowego GCP (format: XXXXXX-XXXXXX-XXXXXX)"
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account))
    error_message = "Billing account ID musi mieć format XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "org_id" {
  description = "ID organizacji GCP (opcjonalne – puste jeśli projekt bez organizacji)"
  type        = string
  default     = ""
}

variable "folder_id" {
  description = "ID folderu GCP (opcjonalne – jeśli projekt ma być w folderze zamiast w root organizacji)"
  type        = string
  default     = ""
}
