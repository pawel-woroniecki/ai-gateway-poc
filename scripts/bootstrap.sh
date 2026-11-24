#!/usr/bin/env bash
# ============================================================================
# AI Gateway PoC – Bootstrap
# Inicjalizacja projektu GCP: service account, włączenie API
#
# State w centralnym buckecie GCS: reinventor-terraform-states
# Prefix: ai-gateway-poc-{suffix}/bootstrap
#
# Użycie:
#   ./scripts/bootstrap.sh
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
auto_detect_project

: "${PROJECT_ID:?Ustaw zmienną PROJECT_ID lub najpierw uruchom create-project.sh}"
: "${SUFFIX:?Ustaw zmienną SUFFIX lub najpierw uruchom create-project.sh}"
REGION="${REGION:-europe-central2}"

BOOTSTRAP_DIR="${ROOT_DIR}/terraform/bootstrap"
BOOTSTRAP_PREFIX="ai-gateway-poc-${SUFFIX}/bootstrap"

echo "=== AI Gateway PoC – Bootstrap ==="
echo "Project:  ${PROJECT_ID}"
echo "Suffix:   ${SUFFIX}"
echo "Region:   ${REGION}"
echo "State:    gs://${CENTRAL_BUCKET}/${BOOTSTRAP_PREFIX}/"
echo ""

# Upewnij się, że gcloud wskazuje na właściwy projekt
gcloud config set project "${PROJECT_ID}"

# Terraform bootstrap
cd "${BOOTSTRAP_DIR}"

echo ">>> terraform init..."
terraform init \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${BOOTSTRAP_PREFIX}" \
  -input=false

echo ">>> terraform apply..."
terraform apply \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}"

# Pobranie outputów
SA_EMAIL=$(terraform output -raw terraform_sa_email)

echo ""
echo "=== Bootstrap zakończony ==="
echo "Terraform SA: ${SA_EMAIL}"
echo ""
echo "Następny krok:"
echo "  ./scripts/up.sh"
