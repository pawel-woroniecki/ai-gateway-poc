#!/usr/bin/env bash
# ============================================================================
# AI Gateway PoC – Bootstrap
# Inicjalizacja projektu GCP: service account, włączenie API
#
# State w centralnym buckecie GCS: reinventor-terraform-states
# Prefix: ai-gateway-poc-{suffix}/bootstrap
#
# Użycie:
#   ./scripts/bootstrap.sh           # odczyt z .project-env
#   ./scripts/bootstrap.sh abcd      # podany suffix
#
# PROJECT_ID i SUFFIX odczytywane automatycznie z .project-env
# (utworzonego przez create-project.sh).
# Można też ustawić ręcznie:
#   export PROJECT_ID="reinventor-ai-gateway-poc-xxxx"
#   export SUFFIX="xxxx"
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"
auto_detect_project "${1:-}"
check_requirements

: "${PROJECT_ID:?Ustaw zmienną PROJECT_ID lub najpierw uruchom create-project.sh}"
: "${SUFFIX:?Ustaw zmienną SUFFIX lub najpierw uruchom create-project.sh}"
REGION="${REGION:-europe-central2}"

BOOTSTRAP_PREFIX=$(state_prefix "bootstrap")

echo "=== AI Gateway PoC – Bootstrap ==="
echo "Project:  ${PROJECT_ID}"
echo "Suffix:   ${SUFFIX}"
echo "Region:   ${REGION}"
echo "State:    gs://${CENTRAL_BUCKET}/${BOOTSTRAP_PREFIX}/"
echo ""

# Upewnij się, że gcloud wskazuje na właściwy projekt
gcloud config set project "${PROJECT_ID}"

# Terraform bootstrap
cd "${ROOT_DIR}/terraform/bootstrap"

echo ">>> terraform init..."
if ! terraform init -reconfigure \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${BOOTSTRAP_PREFIX}" \
  -input=false; then
  echo "BŁĄD: terraform init nie powiodło się." >&2
  exit 1
fi

echo ">>> terraform apply..."
if ! terraform apply \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}"; then
  echo "BŁĄD: terraform apply nie powiodło się." >&2
  exit 1
fi

# Pobranie outputów z walidacją
SA_EMAIL=$(terraform output -raw terraform_sa_email 2>/dev/null) || true

if [ -z "$SA_EMAIL" ]; then
  echo "BŁĄD: Nie udało się pobrać terraform_sa_email z outputów." >&2
  exit 1
fi

echo ""
echo "=== Bootstrap zakończony ==="
echo "Terraform SA: ${SA_EMAIL}"
echo ""
echo "Następny krok:"
echo "  ./scripts/up.sh"
