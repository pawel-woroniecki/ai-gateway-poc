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
#   export BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"
#   ./scripts/create-project.sh
#
# Opcjonalnie:
#   export ORG_ID="123456789"       # jeśli masz organizację
#   export FOLDER_ID="123456789"    # jeśli projekt ma być w folderze
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"

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
terraform init \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${PROJECT_STATE_PREFIX}" \
  -input=false

# Buduj listę zmiennych
TF_VARS=(
  -var="billing_account=${BILLING_ACCOUNT}"
)
[ -n "$ORG_ID" ] && TF_VARS+=(-var="org_id=${ORG_ID}")
[ -n "$FOLDER_ID" ] && TF_VARS+=(-var="folder_id=${FOLDER_ID}")

echo ">>> terraform apply..."
terraform apply "${TF_VARS[@]}"

# Pobranie outputów
NEW_PROJECT_ID=$(terraform output -raw project_id)
NEW_SUFFIX=$(terraform output -raw suffix)

# Zapisz do .project-env (automatyczna detekcja w pozostałych skryptach)
cat > "${ROOT_DIR}/.project-env" <<EOF
# Wygenerowane automatycznie przez create-project.sh
# $(date -u +"%Y-%m-%d %H:%M:%S UTC")
PROJECT_ID=${NEW_PROJECT_ID}
SUFFIX=${NEW_SUFFIX}
EOF

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
