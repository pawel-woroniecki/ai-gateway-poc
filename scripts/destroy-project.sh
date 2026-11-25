#!/usr/bin/env bash
# ============================================================================
# AI Gateway PoC – Usuwanie projektu GCP
#
# Niszczy projekt GCP utworzony przez create-project.sh.
# Dzięki deletion_policy="DELETE" i losowemu suffixowi można natychmiast
# utworzyć nowy projekt bez czekania na 30-dniowe permanentne usunięcie.
#
# Czyści WSZYSTKIE terraform state z GCS (project, bootstrap, dev).
#
# Użycie:
#   ./scripts/destroy-project.sh          # odczyt z .project-env
#   ./scripts/destroy-project.sh abcd     # podany suffix
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"
check_requirements

: "${BILLING_ACCOUNT:?Ustaw zmienną BILLING_ACCOUNT, np. export BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX}"

ORG_ID="${ORG_ID:-}"
FOLDER_ID="${FOLDER_ID:-}"

# Odczyt suffixu z argumentu lub .project-env
auto_detect_project "${1:-}"

if [ -z "${SUFFIX:-}" ]; then
  echo "BŁĄD: Nie znaleziono SUFFIX. Podaj jako argument lub uruchom create-project.sh." >&2
  exit 1
fi

PROJECT_STATE_PREFIX=$(state_prefix "project")

cd "$PROJECT_TF_DIR"

# Init z remote backend
echo ">>> terraform init..."
if ! terraform init -reconfigure \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${PROJECT_STATE_PREFIX}" \
  -input=false; then
  echo "BŁĄD: terraform init nie powiodło się." >&2
  exit 1
fi

# Sprawdź czy state zawiera projekt
CURRENT_PROJECT=$(terraform output -raw project_id 2>/dev/null || echo "")

if [ -z "$CURRENT_PROJECT" ]; then
  echo "Brak projektu w remote state – nie ma czego usuwać."
  echo "Czyszczenie state z GCS..."
  # Mimo braku projektu, wyczyść ewentualne pozostałości state
  for prefix in \
    "$(state_prefix "project")" \
    "$(state_prefix "bootstrap")" \
    "$(state_prefix "dev")"; do
    gsutil -m rm -r "gs://${CENTRAL_BUCKET}/${prefix}/" 2>/dev/null || true
  done
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
  -var="suffix=${SUFFIX}"
)
[ -n "$ORG_ID" ] && TF_VARS+=(-var="org_id=${ORG_ID}")
[ -n "$FOLDER_ID" ] && TF_VARS+=(-var="folder_id=${FOLDER_ID}")

echo ""
echo ">>> terraform destroy..."
DESTROY_EXIT=0
terraform destroy "${TF_VARS[@]}" || DESTROY_EXIT=$?

if [ $DESTROY_EXIT -ne 0 ]; then
  echo "UWAGA: terraform destroy zwrócił kod $DESTROY_EXIT." >&2
  echo "Projekt mógł zostać usunięty, ale zapis stanu do GCS mógł się nie powieść." >&2
  echo "Kontynuuję czyszczenie..." >&2
fi

# Czyszczenie WSZYSTKICH terraform state i lock z GCS
echo ">>> Czyszczenie terraform state z GCS..."
for prefix in \
  "$(state_prefix "project")" \
  "$(state_prefix "bootstrap")" \
  "$(state_prefix "dev")"; do
  if gsutil -m rm -r "gs://${CENTRAL_BUCKET}/${prefix}/" 2>/dev/null; then
    echo "  Usunięto: gs://${CENTRAL_BUCKET}/${prefix}/"
  else
    echo "  Brak/już usunięte: ${prefix}"
  fi
done

# Czyszczenie lokalnych plików errored.tfstate
rm -f "${PROJECT_TF_DIR}/errored.tfstate"
rm -f "${PROJECT_TF_DIR}/errored.tfstate.backup"

# Usuń .project-env
rm -f "${ROOT_DIR}/.project-env"

# Weryfikacja – czy projekt został usunięty
echo ">>> Weryfikacja usunięcia projektu..."
if gcloud projects describe "$CURRENT_PROJECT" >/dev/null 2>&1; then
  echo "UWAGA: Projekt $CURRENT_PROJECT nadal widoczny w GCP – usunięcie może potrwać kilka sekund." >&2
else
  echo "  Projekt usunięty z GCP."
fi

echo ""
echo "============================================"
echo " Projekt $CURRENT_PROJECT usunięty."
echo " Plik .project-env usunięty."
echo " State GCS wyczyszczony."
echo "============================================"
echo ""
echo " Aby utworzyć nowy projekt:"
echo "   ./scripts/create-project.sh"
echo "============================================"
