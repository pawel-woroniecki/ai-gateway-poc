#!/usr/bin/env bash
# ============================================================================
# down.sh – Usuwanie środowiska AI Gateway PoC
# Kolejność odwrotna: Helm → K8s resources → Terraform destroy
#
# State w centralnym buckecie GCS: reinventor-terraform-states
# Prefix: ai-gateway-poc-{suffix}/dev
#
# Użycie:
#   ./scripts/down.sh           # odczyt z .project-env
#   ./scripts/down.sh abcd      # podany suffix
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"
auto_detect_project "${1:-}"

# Sprawdzenie dodatkowych wymagań
check_requirements
for cmd in kubectl helm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "BŁĄD: Brak wymaganego narzędzia: $cmd" >&2
    exit 1
  fi
done

: "${PROJECT_ID:?Ustaw zmienną PROJECT_ID lub najpierw uruchom create-project.sh}"
: "${SUFFIX:?Ustaw zmienną SUFFIX lub najpierw uruchom create-project.sh}"
REGION="${REGION:-europe-central2}"
ZONE="${ZONE:-europe-central2-a}"

DEV_STATE_PREFIX=$(state_prefix "dev")

echo "============================================"
echo " AI Gateway PoC – down.sh"
echo " Projekt: $PROJECT_ID"
echo " State:   gs://${CENTRAL_BUCKET}/${DEV_STATE_PREFIX}/"
echo " UWAGA: To usunie wszystkie zasoby!"
echo "============================================"
echo ""
read -p "Kontynuować? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Anulowano."
  exit 0
fi

# --- 1. Helm uninstall ---
echo ""
echo ">>> [1/4] Helm uninstall – LiteLLM..."
helm uninstall litellm 2>/dev/null || echo "  (nie znaleziono release)"

# --- 2. Usunięcie pozostałych K8s resources ---
echo ""
echo ">>> [2/4] Usuwanie K8s resources..."
kubectl delete -f "$ROOT_DIR/mock/k8s.yaml" 2>/dev/null || echo "  (mock-backend nie znaleziony)"
kubectl delete secret litellm-secrets litellm-env 2>/dev/null || true
kubectl delete configmap litellm-config 2>/dev/null || true

# --- 3. Usunięcie obrazu z GCR ---
echo ""
echo ">>> [3/4] Usuwanie obrazu z GCR..."
gcloud container images delete "gcr.io/${PROJECT_ID}/mock-backend:latest" \
  --force-delete-tags --quiet 2>/dev/null || echo "  (obraz nie znaleziony)"

# --- 4. Terraform destroy ---
echo ""
echo ">>> [4/4] Terraform destroy – infrastruktura..."

cd "$ROOT_DIR/terraform/environments/dev"

if ! terraform init -reconfigure \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${DEV_STATE_PREFIX}" \
  -input=false; then
  echo "BŁĄD: terraform init nie powiodło się." >&2
  exit 1
fi

if ! terraform destroy \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="zone=${ZONE}" \
  -auto-approve; then
  echo "BŁĄD: terraform destroy nie powiodło się." >&2
  exit 1
fi

echo ""
echo "============================================"
echo " AI Gateway PoC – USUNIĘTE"
echo "============================================"
echo ""
echo " Aby usunąć również cały projekt GCP:"
echo "   ./scripts/destroy-project.sh"
echo "============================================"
