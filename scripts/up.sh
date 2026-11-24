#!/usr/bin/env bash
# ============================================================================
# up.sh – Stawianie środowiska AI Gateway PoC
# Kolejność: Terraform infra → kubectl config → mock backend → Helm release
#
# State w centralnym buckecie GCS: reinventor-terraform-states
# Prefix: ai-gateway-poc-{suffix}/dev
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"
auto_detect_project

# --- Sprawdzenie wymagań ---
check_requirements() {
  local missing=()
  command -v terraform >/dev/null 2>&1 || missing+=("terraform")
  command -v gcloud >/dev/null 2>&1    || missing+=("gcloud")
  command -v kubectl >/dev/null 2>&1   || missing+=("kubectl")
  command -v helm >/dev/null 2>&1      || missing+=("helm")
  command -v docker >/dev/null 2>&1    || missing+=("docker")

  if [ ${#missing[@]} -gt 0 ]; then
    echo "BŁĄD: Brakuje wymaganych narzędzi: ${missing[*]}" >&2
    exit 1
  fi
}

check_requirements

if [ -z "${PROJECT_ID:-}" ]; then
  echo "BŁĄD: PROJECT_ID nie jest ustawione. Uruchom najpierw create-project.sh" >&2
  exit 1
fi
if [ -z "${SUFFIX:-}" ]; then
  echo "BŁĄD: SUFFIX nie jest ustawiony. Sprawdź plik .project-env" >&2
  exit 1
fi

echo "============================================"
echo " AI Gateway PoC – UP"
echo " Projekt: ${PROJECT_ID}"
echo "============================================"

# --- 1. Terraform infra (GKE, VPC, SA) ---
echo ""
echo ">>> [1/4] Terraform apply – infrastruktura..."
cd "${ROOT_DIR}/terraform/environments/dev"

if ! terraform init \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=ai-gateway-poc-${SUFFIX}/dev"; then
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
echo ">>> [2/4] Konfiguracja kubectl..."
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
echo ">>> [3/4] Deploy mock backend..."
cd "$ROOT_DIR/mock"

if ! docker build -t "gcr.io/${PROJECT_ID}/mock-backend:latest" .; then
  echo "BŁĄD: Docker build nie powiodło się." >&2
  exit 1
fi

if ! docker push "gcr.io/${PROJECT_ID}/mock-backend:latest"; then
  echo "BŁĄD: Docker push do GCR nie powiodło się." >&2
  exit 1
fi

sed "s|image: mock-backend:latest|image: gcr.io/${PROJECT_ID}/mock-backend:latest|" \
  k8s.yaml | kubectl apply -f -

if ! kubectl rollout status deployment/mock-backend --timeout=120s; then
  echo "BŁĄD: Mock backend nie wystartował w ciągu 120s." >&2
  exit 1
fi
echo "  Mock backend działa."

# --- 4. Helm install LiteLLM ---
echo ""
echo ">>> [4/4] Helm install – LiteLLM..."
cd "$ROOT_DIR"

if ! helm upgrade --install litellm oci://ghcr.io/berriai/litellm-helm \
  -f helm/values/litellm-dev.yaml \
  --set "serviceAccount.annotations.iam\.gke\.io/gcp-service-account=${LITELLM_SA}" \
  --wait \
  --timeout 5m; then
  echo "BŁĄD: Helm install LiteLLM nie powiodło się." >&2
  exit 1
fi

echo ""
echo "============================================"
echo " AI Gateway PoC – GOTOWE"
echo "============================================"
echo ""
echo " Master Key: sk-aigw-master-poc-dev"
echo ""
echo " Port-forward do LiteLLM:"
echo "   kubectl port-forward svc/litellm 4000:4000"
echo ""
echo " Test:"
echo "   curl http://localhost:4000/health/liveliness"
echo ""
echo " Test mock modelu:"
echo "   curl http://localhost:4000/v1/chat/completions \\"
echo "     -H 'Authorization: Bearer sk-aigw-master-poc-dev' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"model\": \"mock-local\", \"messages\": [{\"role\": \"user\", \"content\": \"test\"}]}'"
