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
    echo "BŁĄD: Brakujące narzędzia: ${missing[*]}" >&2
    exit 1
  fi
}
check_requirements

: "${PROJECT_ID:?Ustaw zmienną PROJECT_ID lub najpierw uruchom create-project.sh}"
: "${SUFFIX:?Ustaw zmienną SUFFIX lub najpierw uruchom create-project.sh}"
REGION="${REGION:-europe-central2}"
ZONE="${ZONE:-europe-central2-a}"
CLUSTER_NAME="${CLUSTER_NAME:-ai-gateway-cluster}"

DEV_STATE_PREFIX="ai-gateway-poc-${SUFFIX}/dev"

echo "============================================"
echo " AI Gateway PoC – up.sh"
echo " Projekt: $PROJECT_ID"
echo " Suffix:  $SUFFIX"
echo " Region:  $REGION"
echo " Zona:    $ZONE"
echo " State:   gs://${CENTRAL_BUCKET}/${DEV_STATE_PREFIX}/"
echo "============================================"

# --- 1. Terraform apply (infrastruktura) ---
echo ""
echo ">>> [1/5] Terraform apply – infrastruktura..."
cd "$ROOT_DIR/terraform/environments/dev"

if ! terraform init \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${DEV_STATE_PREFIX}" \
  -input=false; then
  echo "BŁĄD: terraform init nie powiodło się." >&2
  exit 1
fi

if ! terraform apply \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="zone=${ZONE}" \
  -auto-approve; then
  echo "BŁĄD: terraform apply nie powiodło się." >&2
  exit 1
fi

# Pobierz outputy
LITELLM_SA=$(terraform output -raw litellm_sa_email 2>/dev/null) || true
if [ -z "$LITELLM_SA" ]; then
  echo "BŁĄD: Nie udało się pobrać litellm_sa_email z outputów Terraform." >&2
  exit 1
fi

echo "  Infrastruktura gotowa."

# --- 2. kubectl config ---
echo ""
echo ">>> [2/5] Konfiguracja kubectl..."
if ! gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --zone "$ZONE" \
  --project "$PROJECT_ID"; then
  echo "BŁĄD: Nie udało się pobrać credentials klastra GKE." >&2
  exit 1
fi

echo "  kubectl skonfigurowany."

# --- 3. Mock backend ---
echo ""
echo ">>> [3/5] Deploy mock backend..."
cd "$ROOT_DIR/mock"

# Build mock image i push do GCR (lub użyj local z docker build)
# Dla PoC: budujemy lokalnie i ładujemy do klastra
if ! docker build -t "gcr.io/${PROJECT_ID}/mock-backend:latest" .; then
  echo "BŁĄD: Docker build nie powiodło się." >&2
  exit 1
fi

if ! docker push "gcr.io/${PROJECT_ID}/mock-backend:latest"; then
  echo "BŁĄD: Docker push do GCR nie powiodło się." >&2
  exit 1
fi

# Update image w manifeście i apply
sed "s|image: mock-backend:latest|image: gcr.io/${PROJECT_ID}/mock-backend:latest|" \
  k8s.yaml | kubectl apply -f -

if ! kubectl rollout status deployment/mock-backend --timeout=120s; then
  echo "BŁĄD: Mock backend nie wystartował w ciągu 120s." >&2
  exit 1
fi
echo "  Mock backend działa."

# --- 4. Secrets dla LiteLLM ---
echo ""
echo ">>> [4/5] Tworzenie secrets..."

LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-aigw-master-$(openssl rand -hex 8)}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

kubectl create secret generic litellm-secrets \
  --from-literal=master-key="$LITELLM_MASTER_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic litellm-env \
  --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  --from-literal=LANGFUSE_PUBLIC_KEY="${LANGFUSE_PUBLIC_KEY:-}" \
  --from-literal=LANGFUSE_SECRET_KEY="${LANGFUSE_SECRET_KEY:-}" \
  --from-literal=LANGFUSE_HOST="${LANGFUSE_HOST:-http://langfuse:3000}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ConfigMap z konfiguracja LiteLLM
kubectl create configmap litellm-config \
  --from-file=config.yaml="$ROOT_DIR/config/litellm/config.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  Secrets i ConfigMap utworzone."

# --- 5. Helm install LiteLLM ---
echo ""
echo ">>> [5/5] Helm install – LiteLLM..."
cd "$ROOT_DIR"

# Dodaj repo jeśli nie istnieje
helm repo add litellm https://berriai.github.io/litellm/ 2>/dev/null || true
helm repo update

if ! helm upgrade --install litellm litellm/litellm-helm \
  -f helm/values/litellm-dev.yaml \
  --set "serviceAccount.annotations.iam\.gke\.io/gcp-service-account=${LITELLM_SA}" \
  --set "extraEnvVars[1].name=GCP_PROJECT_ID" \
  --set "extraEnvVars[1].value=${PROJECT_ID}" \
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
echo " LiteLLM Master Key: $LITELLM_MASTER_KEY"
echo ""
echo " Port-forward do LiteLLM:"
echo "   kubectl port-forward svc/litellm 4000:4000"
echo ""
echo " Test:"
echo "   curl http://localhost:4000/health/liveliness"
echo ""
echo " Szacowany koszt sesji: ~\$0.50"
echo " Pamiętaj: down.sh po zakończeniu testów!"
echo "============================================"
