#!/usr/bin/env bash
# ============================================================================
# up.sh – Stawianie środowiska AI Gateway PoC
# Kolejność: Terraform infra → kubectl config → mock backend → Helm release
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Wymagane zmienne ---
: "${PROJECT_ID:?Ustaw zmienną PROJECT_ID}"
REGION="${REGION:-europe-central2}"
ZONE="${ZONE:-europe-central2-a}"
CLUSTER_NAME="${CLUSTER_NAME:-ai-gateway-cluster}"

echo "============================================"
echo " AI Gateway PoC – up.sh"
echo " Projekt: $PROJECT_ID"
echo " Region:  $REGION"
echo " Zona:    $ZONE"
echo "============================================"

# --- 1. Terraform state bucket (z bootstrap) ---
STATE_BUCKET="${PROJECT_ID}-tfstate"

# --- 2. Terraform apply (infrastruktura) ---
echo ""
echo ">>> [1/5] Terraform apply – infrastruktura..."
cd "$ROOT_DIR/terraform/environments/dev"

terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=ai-gateway/dev"

terraform apply \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="zone=${ZONE}" \
  -var="state_bucket=${STATE_BUCKET}" \
  -auto-approve

# Pobierz outputy
LITELLM_SA=$(terraform output -raw litellm_sa_email)

echo "  Infrastruktura gotowa."

# --- 3. kubectl config ---
echo ""
echo ">>> [2/5] Konfiguracja kubectl..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --zone "$ZONE" \
  --project "$PROJECT_ID"

echo "  kubectl skonfigurowany."

# --- 4. Mock backend ---
echo ""
echo ">>> [3/5] Deploy mock backend..."
cd "$ROOT_DIR/mock"

# Build mock image i push do GCR (lub użyj local z docker build)
# Dla PoC: budujemy lokalnie i ładujemy do klastra
docker build -t "gcr.io/${PROJECT_ID}/mock-backend:latest" .
docker push "gcr.io/${PROJECT_ID}/mock-backend:latest"

# Update image w manifeście i apply
sed "s|image: mock-backend:latest|image: gcr.io/${PROJECT_ID}/mock-backend:latest|" \
  k8s.yaml | kubectl apply -f -

kubectl rollout status deployment/mock-backend --timeout=120s
echo "  Mock backend działa."

# --- 5. Secrets dla LiteLLM ---
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

# --- 6. Helm install LiteLLM ---
echo ""
echo ">>> [5/5] Helm install – LiteLLM..."
cd "$ROOT_DIR"

# Dodaj repo jeśli nie istnieje
helm repo add litellm https://berriai.github.io/litellm/ 2>/dev/null || true
helm repo update

helm upgrade --install litellm litellm/litellm-helm \
  -f helm/values/litellm-dev.yaml \
  --set "serviceAccount.annotations.iam\.gke\.io/gcp-service-account=${LITELLM_SA}" \
  --set "extraEnvVars[1].name=GCP_PROJECT_ID" \
  --set "extraEnvVars[1].value=${PROJECT_ID}" \
  --wait \
  --timeout 5m

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
