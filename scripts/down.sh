#!/usr/bin/env bash
# ============================================================================
# down.sh – Usuwanie środowiska AI Gateway PoC
# Kolejność odwrotna: Helm → K8s resources → Terraform destroy
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

: "${PROJECT_ID:?Ustaw zmienną PROJECT_ID}"
REGION="${REGION:-europe-central2}"
ZONE="${ZONE:-europe-central2-a}"

echo "============================================"
echo " AI Gateway PoC – down.sh"
echo " Projekt: $PROJECT_ID"
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
STATE_BUCKET="${PROJECT_ID}-tfstate"

cd "$ROOT_DIR/terraform/environments/dev"

terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=ai-gateway/dev"

terraform destroy \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="zone=${ZONE}" \
  -var="state_bucket=${STATE_BUCKET}" \
  -auto-approve

echo ""
echo "============================================"
echo " AI Gateway PoC – USUNIĘTE"
echo "============================================"
echo ""
echo " Terraform state bucket ($STATE_BUCKET) pozostał"
echo " – usuń ręcznie jeśli nie potrzebujesz:"
echo "   gsutil rm -r gs://${STATE_BUCKET}"
echo "============================================"
