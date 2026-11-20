#!/usr/bin/env bash
# ============================================================================
# AI Gateway PoC – Bootstrap
# Inicjalizacja projektu GCP: bucket na state, service account, API
#
# Użycie:
#   export PROJECT_ID="ai-gateway-poc"
#   ./scripts/bootstrap.sh
# ============================================================================
set -euo pipefail

: "${PROJECT_ID:?Ustaw zmienną PROJECT_ID, np. export PROJECT_ID=ai-gateway-poc}"
REGION="${REGION:-europe-central2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/../terraform/bootstrap"

echo "=== AI Gateway PoC – Bootstrap ==="
echo "Project:  ${PROJECT_ID}"
echo "Region:   ${REGION}"
echo ""

# Upewnij się, że gcloud wskazuje na właściwy projekt
gcloud config set project "${PROJECT_ID}"

# Terraform bootstrap
cd "${BOOTSTRAP_DIR}"

if [ ! -d ".terraform" ]; then
  echo ">>> terraform init..."
  terraform init
fi

echo ">>> terraform apply..."
terraform apply \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}"

# Pobranie outputów
STATE_BUCKET=$(terraform output -raw state_bucket)
SA_EMAIL=$(terraform output -raw terraform_sa_email)

echo ""
echo "=== Bootstrap zakończony ==="
echo "State bucket: ${STATE_BUCKET}"
echo "Terraform SA: ${SA_EMAIL}"
echo ""
echo "Następny krok:"
echo "  cd terraform/environments/dev"
echo "  terraform init"
echo "  # (uzupełnij terraform.tfvars)"
echo "  terraform apply"
