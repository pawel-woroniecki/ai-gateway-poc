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

# Region Artifact Registry (musi zgadzać się z var.region w Terraform)
AR_REGION="${AR_REGION:-europe-central2}"

# --- Budowanie pełnej ścieżki obrazu w Artifact Registry ---
# Użycie: ar_image "mock-backend"
#   → europe-central2-docker.pkg.dev/reinventor-ai-gateway-poc-XXXX/ai-gateway/mock-backend
# Wymaga ustawionego PROJECT_ID i AR_REGION.
ar_image() {
  local image_name="$1"
  echo "${AR_REGION}-docker.pkg.dev/${PROJECT_ID}/ai-gateway/${image_name}"
}

# --- Znajdowanie wolnego portu lokalnego ---
# Sprawdza czy podany port jest wolny, jeśli nie – szuka kolejnego.
# Cloud Shell nie ma lsof, więc używamy /dev/tcp lub ss.
# Użycie: LOCAL_PORT=$(find_free_port 4000)
find_free_port() {
  local port="${1:-4000}"
  local max_attempts=20
  for (( i=0; i<max_attempts; i++ )); do
    if ! (echo >/dev/tcp/127.0.0.1/$port) 2>/dev/null; then
      echo "$port"
      return 0
    fi
    port=$((port + 1))
  done
  echo "BŁĄD: Nie znaleziono wolnego portu w zakresie ${1}–$((${1}+max_attempts-1))" >&2
  return 1
}

# --- Uruchomienie port-forward na wolnym porcie ---
# Użycie: start_port_forward "svc/litellm" 4000
# Ustawia zmienną PF_PORT na wybrany port i uruchamia port-forward w tle.
start_port_forward() {
  local service="$1"
  local target_port="${2:-4000}"
  local base_port="${3:-$target_port}"

  # Ubij istniejące port-forwardy do tego samego service
  pkill -f "port-forward ${service}" 2>/dev/null || true
  sleep 1

  PF_PORT=$(find_free_port "$base_port")
  echo "  Port-forward: localhost:${PF_PORT} → ${service}:${target_port}"
  kubectl port-forward "$service" "${PF_PORT}:${target_port}" &
  PF_PID=$!
  sleep 2

  # Sprawdź czy proces jeszcze żyje
  if ! kill -0 "$PF_PID" 2>/dev/null; then
    echo "BŁĄD: Port-forward nie wystartował." >&2
    return 1
  fi
}
