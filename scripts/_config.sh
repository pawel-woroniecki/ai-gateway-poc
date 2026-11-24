#!/usr/bin/env bash
# ============================================================================
# _config.sh – wspólna konfiguracja dla skryptów AI Gateway PoC
#
# Sourcowany przez pozostałe skrypty:
#   source "${SCRIPT_DIR}/_config.sh"
# ============================================================================

# Centralny bucket na Terraform state (w osobnym projekcie GCP)
CENTRAL_BUCKET="reinventor-terraform-states"

# Prefix stały dla modułu project (suffix jeszcze nie istnieje przy tworzeniu)
PROJECT_STATE_PREFIX="ai-gateway-poc/project"

# Ścieżki (SCRIPT_DIR musi być ustawiony przez skrypt wywołujący)
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_TF_DIR="${ROOT_DIR}/terraform/project"

# --- Auto-detekcja PROJECT_ID i SUFFIX ---
# Sourcuje .project-env jeśli istnieje i zmienne nie są ustawione przez env
auto_detect_project() {
  if [ -z "${PROJECT_ID:-}" ] && [ -f "${ROOT_DIR}/.project-env" ]; then
    echo ">>> Odczytywanie PROJECT_ID z .project-env..."
    source "${ROOT_DIR}/.project-env"
  fi
}
