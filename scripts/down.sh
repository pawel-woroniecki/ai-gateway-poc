#!/usr/bin/env bash
# ============================================================================
# down.sh – Usuwanie środowiska AI Gateway PoC
# Kolejność odwrotna: Helm → K8s resources → Terraform destroy
#
# Optymalizacja: jeśli klaster GKE nie istnieje, kroki Helm/kubectl
# są pomijane (brak timeoutów na nieistniejący API server).
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

# --- 0. Sprawdzenie czy klaster GKE istnieje ---
CLUSTER_NAME="ai-gateway-poc"
GKE_EXISTS=false
echo ""
echo ">>> [0/5] Sprawdzanie klastra GKE..."
if gcloud container clusters describe "$CLUSTER_NAME" \
     --zone="$ZONE" --project="$PROJECT_ID" \
     --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
  GKE_EXISTS=true
  echo "  Klaster $CLUSTER_NAME istnieje – pobieranie credentials..."
  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone="$ZONE" --project="$PROJECT_ID" --quiet
else
  echo "  Klaster nie istnieje – pomijam kroki Helm/kubectl (2–3)."
fi

# --- 1. Ubij aktywne port-forwardy ---
echo ""
echo ">>> [1/5] Ubijanie port-forwardów..."
pkill -f "port-forward" 2>/dev/null || true
echo "  Gotowe."

if $GKE_EXISTS; then
  # --- 2. Helm uninstall ---
  echo ""
  echo ">>> [2/5] Helm uninstall – LiteLLM..."
  helm uninstall litellm -n litellm 2>/dev/null || echo "  (nie znaleziono release)"

  # --- 3. Usunięcie pozostałych K8s resources ---
  echo ""
  echo ">>> [3/5] Usuwanie K8s resources..."
  kubectl delete -f "$ROOT_DIR/k8s/mock-backend.yaml" 2>/dev/null || echo "  (mock-backend nie znaleziony)"
else
  echo ""
  echo ">>> [2/5] Helm uninstall – pominięto (brak klastra)"
  echo ">>> [3/5] K8s resources – pominięto (brak klastra)"
fi

# --- 4. Usunięcie obrazu z Artifact Registry ---
echo ""
echo ">>> [4/5] Usuwanie obrazu z Artifact Registry..."
MOCK_IMAGE="$(ar_image mock-backend):latest"
gcloud artifacts docker images delete "$MOCK_IMAGE" \
  --delete-tags --quiet 2>/dev/null || echo "  (obraz nie znaleziony lub registry nie istnieje)"

# --- 5. Terraform destroy ---
echo ""
echo ">>> [5/5] Terraform destroy – infrastruktura..."

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
