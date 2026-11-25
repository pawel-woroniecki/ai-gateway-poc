#!/usr/bin/env bash
# ============================================================================
# _config.sh – wspólna konfiguracja dla skryptów AI Gateway PoC
#
# Sourcowany przez pozostałe skrypty:
#   source "${SCRIPT_DIR}/_config.sh"
#
# Konwencja state w GCS:
#   gs://CENTRAL_BUCKET/ai-gateway-poc-SUFFIX/project
#   gs://CENTRAL_BUCKET/ai-gateway-poc-SUFFIX/bootstrap
#   gs://CENTRAL_BUCKET/ai-gateway-poc-SUFFIX/dev
#
# Dzięki temu każdy projekt (suffix) ma niezależne state'y
# i wiele projektów może współistnieć równolegle.
# ============================================================================

# Konto billingowe GCP (nadpisywane przez: export BILLING_ACCOUNT="...")
BILLING_ACCOUNT="${BILLING_ACCOUNT:-017C3F-481026-534AC8}"

# Bazowa nazwa projektu GCP
PROJECT_NAME_BASE="reinventor-ai-gateway-poc"

# Centralny bucket na Terraform state (w osobnym projekcie GCP)
CENTRAL_BUCKET="reinventor-terraform-states"

# Bazowy prefix state w GCS (suffix dodawany dynamicznie)
STATE_PREFIX_BASE="ai-gateway-poc"

# Ścieżki (SCRIPT_DIR musi być ustawiony przez skrypt wywołujący)
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_TF_DIR="${ROOT_DIR}/terraform/project"

# --- Funkcja: budowanie prefixu state w GCS ---
# Użycie: state_prefix "project"   → ai-gateway-poc-XXXX/project
#          state_prefix "bootstrap" → ai-gateway-poc-XXXX/bootstrap
#          state_prefix "dev"       → ai-gateway-poc-XXXX/dev
# Wymaga ustawionego SUFFIX.
state_prefix() {
  local module="$1"
  echo "${STATE_PREFIX_BASE}-${SUFFIX}/${module}"
}

# --- Sprawdzenie wymagań ---
check_requirements() {
  local missing=()
  command -v terraform >/dev/null 2>&1 || missing+=("terraform")
  command -v gcloud >/dev/null 2>&1    || missing+=("gcloud")

  if [ ${#missing[@]} -gt 0 ]; then
    echo "BŁĄD: Brakujące narzędzia: ${missing[*]}" >&2
    exit 1
  fi
}

# --- Auto-detekcja PROJECT_ID i SUFFIX ---
# Sourcuje .project-env jeśli istnieje i zmienne nie są ustawione.
# Opcjonalny argument: suffix (nadpisuje .project-env)
# Użycie:
#   auto_detect_project          # odczyt z .project-env
#   auto_detect_project "qncd"   # użycie podanego suffixu
auto_detect_project() {
  # Jeśli podano argument – użyj go
  if [ -n "${1:-}" ]; then
    SUFFIX="$1"
    PROJECT_ID="${PROJECT_NAME_BASE}-${SUFFIX}"
    echo ">>> Użycie suffixu z argumentu: ${SUFFIX}"
    return
  fi

  # Fallback: odczyt z .project-env
  if [ -z "${PROJECT_ID:-}" ] && [ -f "${ROOT_DIR}/.project-env" ]; then
    echo ">>> Odczytywanie PROJECT_ID z .project-env..."
    source "${ROOT_DIR}/.project-env"
  fi
}
