#!/usr/bin/env bash
# ============================================================================
# AI Gateway PoC – Tworzenie projektu GCP
#
# Tworzy nowy projekt z losowym 4-literowym suffixem.
# Dzięki unikalnemu suffixowi można usunąć projekt i natychmiast stworzyć
# nowy – bez czekania na permanentne usunięcie starego (30 dni w GCP).
#
# State zapisywany w centralnym buckecie GCS: reinventor-terraform-states
# Prefix: ai-gateway-poc/project
#
# Użycie:
#   ./scripts/create-project.sh
#
# Opcjonalnie:
#   export ORG_ID="123456789"       # jeśli masz organizację
#   export FOLDER_ID="123456789"    # jeśli projekt ma być w folderze
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"

# --- Sprawdzenie wymagań ---
check_requirements() {
  local missing=()
  command -v terraform >/dev/null 2>&1 || missing+=("terraform")
  command -v gcloud >/dev/null 2>&1    || missing+=("gcloud")

  if [ ${#missing[@]} -gt 0 ]; then
    echo "BŁĄD: Brakujące narzędzia: ${missing[*]}" >&2
    echo "Zainstaluj je przed uruchomieniem skryptu." >&2
    exit 1
  fi
}
check_requirements

: "${BILLING_ACCOUNT:?Ustaw zmienną BILLING_ACCOUNT, np. export BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX}"

ORG_ID="${ORG_ID:-}"
FOLDER_ID="${FOLDER_ID:-}"

echo "============================================"
echo " AI Gateway PoC – create-project.sh"
echo " Billing:  $BILLING_ACCOUNT"
[ -n "$ORG_ID" ] && echo " Org ID:   $ORG_ID"
[ -n "$FOLDER_ID" ] && echo " Folder:   $FOLDER_ID"
echo " State:    gs://${CENTRAL_BUCKET}/${PROJECT_STATE_PREFIX}/"
echo "============================================"
echo ""
echo " Zostanie utworzony nowy projekt GCP:"
echo "   reinventor-ai-gateway-poc-XXXX"
echo " (XXXX = losowy suffix)"
echo ""

cd "$PROJECT_TF_DIR"

# Init z remote backend
echo ">>> terraform init..."
if ! terraform init \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${PROJECT_STATE_PREFIX}" \
  -input=false; then
  echo "BŁĄD: terraform init nie powiodło się." >&2
  exit 1
fi

# Buduj listę zmiennych
TF_VARS=(
  -var="billing_account=${BILLING_ACCOUNT}"
)
[ -n "$ORG_ID" ] && TF_VARS+=(-var="org_id=${ORG_ID}")
[ -n "$FOLDER_ID" ] && TF_VARS+=(-var="folder_id=${FOLDER_ID}")

echo ">>> terraform apply..."
if ! terraform apply "${TF_VARS[@]}"; then
  echo "BŁĄD: terraform apply nie powiodło się." >&2
  exit 1
fi

# Pobranie outputów z walidacją
NEW_PROJECT_ID=$(terraform output -raw project_id 2>/dev/null) || true
NEW_SUFFIX=$(terraform output -raw suffix 2>/dev/null) || true

if [ -z "$NEW_PROJECT_ID" ] || [ -z "$NEW_SUFFIX" ]; then
  echo "BŁĄD: Nie udało się pobrać outputów Terraform (project_id, suffix)." >&2
  echo "Sprawdź stan: terraform output" >&2
  exit 1
fi

# Zapisz do .project-env (automatyczna detekcja w pozostałych skryptach)
cat > "${ROOT_DIR}/.project-env" <<EOF
# Wygenerowane automatycznie przez create-project.sh
# $(date -u +"%Y-%m-%d %H:%M:%S UTC")
PROJECT_ID=${NEW_PROJECT_ID}
SUFFIX=${NEW_SUFFIX}
EOF

# Weryfikacja – czy projekt istnieje w GCP
echo ">>> Weryfikacja projektu w GCP..."
if gcloud projects describe "$NEW_PROJECT_ID" >/dev/null 2>&1; then
  echo "  Projekt zweryfikowany w GCP."
else
  echo "UWAGA: Projekt $NEW_PROJECT_ID nie jest jeszcze widoczny w GCP." >&2
  echo "Może to potrwać kilka sekund. Sprawdź ręcznie: gcloud projects describe $NEW_PROJECT_ID" >&2
fi

echo ""
echo "============================================"
echo " Projekt utworzony!"
echo "============================================"
echo ""
echo " Project ID:  $NEW_PROJECT_ID"
echo " Suffix:      $NEW_SUFFIX"
echo " State:       gs://${CENTRAL_BUCKET}/${PROJECT_STATE_PREFIX}/"
echo ""
echo " Plik .project-env zapisany – pozostałe skrypty"
echo " automatycznie odczytają PROJECT_ID i SUFFIX."
echo ""
echo " Następne kroki:"
echo "   ./scripts/bootstrap.sh"
echo "   ./scripts/up.sh"
echo "============================================"
