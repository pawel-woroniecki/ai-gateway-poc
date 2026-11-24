#!/usr/bin/env bash
# ============================================================================
# AI Gateway PoC – Usuwanie projektu GCP
#
# Niszczy projekt GCP utworzony przez create-project.sh.
# Dzięki deletion_policy="DELETE" i losowemu suffixowi można natychmiast
# utworzyć nowy projekt bez czekania na 30-dniowe permanentne usunięcie.
#
# Użycie:
#   export BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"
#   ./scripts/destroy-project.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"

: "${BILLING_ACCOUNT:?Ustaw zmienną BILLING_ACCOUNT, np. export BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX}"

ORG_ID="${ORG_ID:-}"
FOLDER_ID="${FOLDER_ID:-}"

cd "$PROJECT_TF_DIR"

# Init z remote backend
echo ">>> terraform init..."
terraform init \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${PROJECT_STATE_PREFIX}" \
  -input=false

# Sprawdź czy state zawiera projekt
CURRENT_PROJECT=$(terraform output -raw project_id 2>/dev/null || echo "")

if [ -z "$CURRENT_PROJECT" ]; then
  echo "Brak projektu w remote state – nie ma czego usuwać."
  exit 0
fi

echo "============================================"
echo " AI Gateway PoC – destroy-project.sh"
echo "============================================"
echo ""
echo " UWAGA: Zostanie TRWALE usunięty projekt:"
echo "   $CURRENT_PROJECT"
echo ""
echo " Ta operacja jest nieodwracalna!"
echo ""
read -p " Kontynuować? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Anulowano."
  exit 0
fi

# Buduj listę zmiennych
TF_VARS=(
  -var="billing_account=${BILLING_ACCOUNT}"
)
[ -n "$ORG_ID" ] && TF_VARS+=(-var="org_id=${ORG_ID}")
[ -n "$FOLDER_ID" ] && TF_VARS+=(-var="folder_id=${FOLDER_ID}")

echo ""
echo ">>> terraform destroy..."
terraform destroy "${TF_VARS[@]}"

# Usuń .project-env
rm -f "${ROOT_DIR}/.project-env"

echo ""
echo "============================================"
echo " Projekt $CURRENT_PROJECT usunięty."
echo " Plik .project-env usunięty."
echo "============================================"
echo ""
echo " Aby utworzyć nowy projekt:"
echo "   ./scripts/create-project.sh"
echo "============================================"
