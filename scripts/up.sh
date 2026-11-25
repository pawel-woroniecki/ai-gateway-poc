#!/usr/bin/env bash
# ============================================================================
# up.sh – Stawianie środowiska AI Gateway PoC
# Kolejność: Terraform infra → kubectl config → mock backend → Helm release → port-forward
#
# State w centralnym buckecie GCS: reinventor-terraform-states
# Prefix: ai-gateway-poc-{suffix}/dev
#
# Użycie:
#   ./scripts/up.sh           # odczyt z .project-env
#   ./scripts/up.sh abcd      # podany suffix
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

if [ -z "${PROJECT_ID:-}" ]; then
  echo "BŁĄD: PROJECT_ID nie jest ustawione. Uruchom najpierw create-project.sh" >&2
  exit 1
fi
if [ -z "${SUFFIX:-}" ]; then
  echo "BŁĄD: SUFFIX nie jest ustawiony. Sprawdź plik .project-env" >&2
  exit 1
fi

DEV_STATE_PREFIX=$(state_prefix "dev")

echo "============================================"
echo " AI Gateway PoC – UP"
echo " Projekt: ${PROJECT_ID}"
echo " State:   gs://${CENTRAL_BUCKET}/${DEV_STATE_PREFIX}/"
echo "============================================"

# --- 1. Terraform infra (GKE, VPC, SA) ---
echo ""
echo ">>> [1/5] Terraform apply – infrastruktura..."
cd "${ROOT_DIR}/terraform/environments/dev"

if ! terraform init -reconfigure \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${DEV_STATE_PREFIX}"; then
  echo "BŁĄD: Terraform init nie powiodło się." >&2
  exit 1
fi

if ! terraform apply -auto-approve \
  -var="project_id=${PROJECT_ID}"; then

  echo "BŁĄD: Terraform apply nie powiodło się." >&2
  exit 1
fi

# Pobranie outputów
LITELLM_SA=$(terraform output -raw litellm_sa_email 2>/dev/null)
if [ -z "$LITELLM_SA" ]; then
  echo "BŁĄD: Nie udało się pobrać litellm_sa_email z Terraform." >&2
  exit 1
fi

echo "  Infrastruktura gotowa."

# --- 2. kubectl config ---
echo ""
echo ">>> [2/5] Konfiguracja kubectl..."
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null)
CLUSTER_LOCATION=$(terraform output -raw cluster_location 2>/dev/null)

if ! gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --zone "$CLUSTER_LOCATION" \
  --project "$PROJECT_ID"; then
  echo "BŁĄD: Nie udało się skonfigurować kubectl." >&2
  exit 1
fi
echo "  kubectl skonfigurowany."

# --- 3. Mock backend ---
echo ""
echo ">>> [3/5] Deploy mock backend..."

MOCK_IMAGE="$(ar_image mock-backend):latest"
cd "$ROOT_DIR/mock"

# Cloud Build: buduje i pushuje obraz po stronie Google
# (omija problemy z Docker networking w Cloud Shell)
echo "  Cloud Build: budowanie i push obrazu..."
if ! gcloud builds submit \
  --tag "$MOCK_IMAGE" \
  --project "$PROJECT_ID" \
  --quiet; then
  echo "BŁĄD: Cloud Build nie powiodło się." >&2
  exit 1
fi

sed "s|image: mock-backend:latest|image: ${MOCK_IMAGE}|" \
  k8s.yaml | kubectl apply -f -

if ! kubectl rollout status deployment/mock-backend --timeout=120s; then
  echo "BŁĄD: Mock backend nie wystartował w ciągu 120s." >&2
  exit 1
fi
echo "  Mock backend działa."

# --- 4. Helm install LiteLLM ---
echo ""
echo ">>> [4/5] Helm install – LiteLLM..."
cd "$ROOT_DIR"

if ! helm upgrade --install litellm oci://ghcr.io/berriai/litellm-helm \
  -f helm/values/litellm-dev.yaml \
  --set "serviceAccount.annotations.iam\.gke\.io/gcp-service-account=${LITELLM_SA}" \
  --wait \
  --timeout 8m; then
  echo "BŁĄD: Helm install LiteLLM nie powiodło się." >&2
  exit 1
fi

# --- 5. Migracje DB (fallback) ---
echo ""
echo ">>> [5/6] Sprawdzanie migracji bazy danych..."
# Helm migrations job może failować gdy PostgreSQL jeszcze nie jest gotowy.
# Fallback: prisma db push z poda LiteLLM.
if ! kubectl exec deploy/litellm -- python3 -c "
import asyncio
from litellm.proxy.db.prisma_client import PrismaClient
pc = PrismaClient(database_url=None, proxy_logging_obj=None)
asyncio.run(pc.connect())
print('DB OK')
" 2>/dev/null | grep -q "DB OK"; then
  echo "  Tabele nie istnieją – uruchamiam prisma db push..."
  kubectl exec deploy/litellm -- sh -c '
    export DATABASE_URL="postgresql://litellm:litellm-poc-password@litellm-postgresql:5432/litellm"
    export DIRECT_URL="$DATABASE_URL"
    prisma db push --schema=/app/schema.prisma --accept-data-loss
  '
  echo "  Restartuję deployment po migracji..."
  kubectl rollout restart deployment/litellm
  kubectl rollout status deployment/litellm --timeout=180s
  echo "  Migracje zastosowane."
else
  echo "  Tabele OK – migracje przeszły poprawnie."
fi

# --- 6. External IP + Port-forward ---
echo ""
echo ">>> [6/6] Pobieranie External IP i port-forward..."

# Czekaj na External IP (max 2 min)
echo "  Czekam na External IP LoadBalancera..."
for i in $(seq 1 24); do
  EXTERNAL_IP=$(kubectl get svc litellm -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "<pending>" ]; then
    break
  fi
  sleep 5
done

start_port_forward "litellm" 4000

echo ""
echo "============================================"
echo " AI Gateway PoC – GOTOWE"
echo "============================================"
echo ""
echo " Master Key: sk-aigw-master-poc-dev"
echo ""
if [ -n "${EXTERNAL_IP:-}" ]; then
echo " LiteLLM Admin UI (przeglądarka):"
echo "   http://${EXTERNAL_IP}:4000/ui"
echo "   Login: admin / sk-aigw-master-poc-dev"
echo ""
fi
echo " Port-forward (curl z Cloud Shell):"
echo "   localhost:${PF_PORT} → deploy/litellm:4000  (PID: ${PF_PID})"
echo ""
echo " Test:"
echo "   curl http://localhost:${PF_PORT}/health/liveliness"
echo ""
echo " Instrukcja UI: instrukcje/06-litellm-admin-ui.md"
echo ""
echo " Test mock modelu:"
echo "   curl http://localhost:${PF_PORT}/v1/chat/completions \\"
echo "     -H 'Authorization: Bearer sk-aigw-master-poc-dev' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"model\": \"mock-local\", \"messages\": [{\"role\": \"user\", \"content\": \"test\"}]}'"
