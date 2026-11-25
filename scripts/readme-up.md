# up.sh – opis działania

Dokument wyjaśnia krok po kroku co robi skrypt `up.sh`, który stawia pełne środowisko AI Gateway PoC – od infrastruktury po działającą aplikację.

## Cel skryptu

`up.sh` to główny skrypt uruchamiający środowisko. Wykonuje cztery etapy:

1. Tworzy infrastrukturę w GCP (klaster Kubernetes, sieć, konta serwisowe)
2. Konfiguruje dostęp do klastra (kubectl)
3. Buduje i wdraża mock backend (symulowany endpoint LLM)
4. Instaluje LiteLLM – bramkę AI (gateway)

Po uruchomieniu tego skryptu środowisko jest w pełni gotowe do testowania.

## Sposób uruchomienia

```
./scripts/up.sh           # odczyt projektu z .project-env
./scripts/up.sh qkhv      # podany suffix projektu
```

## Kroki realizowane przez skrypt

### 1. Tryb bezpieczny

```bash
set -euo pipefail
```

Każdy błąd natychmiast przerywa wykonanie skryptu.

### 2. Załadowanie konfiguracji i wykrywanie projektu

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"
auto_detect_project "${1:-}"
```

Ładuje wspólną konfigurację i wykrywa projekt (z argumentu lub `.project-env`).

### 3. Sprawdzenie wymagań

```bash
check_requirements
for cmd in kubectl helm docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "BŁĄD: Brak wymaganego narzędzia: $cmd" >&2
    exit 1
  fi
done
```

Oprócz standardowych `terraform` i `gcloud`, skrypt wymaga dodatkowych narzędzi:

- **kubectl** – CLI do zarządzania klastrem Kubernetes
- **helm** – menedżer pakietów Kubernetes (do instalacji LiteLLM)
- **docker** – do budowania obrazu mock backendu

### 4. Walidacja zmiennych

```bash
if [ -z "${PROJECT_ID:-}" ]; then
  echo "BŁĄD: PROJECT_ID nie jest ustawione. Uruchom najpierw create-project.sh" >&2
  exit 1
fi
if [ -z "${SUFFIX:-}" ]; then
  echo "BŁĄD: SUFFIX nie jest ustawiony. Sprawdź plik .project-env" >&2
  exit 1
fi
```

Sprawdzenie, czy `PROJECT_ID` i `SUFFIX` są ustawione.

### 5. Podsumowanie parametrów

```bash
DEV_STATE_PREFIX=$(state_prefix "dev")

echo "============================================"
echo " AI Gateway PoC – UP"
echo " Projekt: ${PROJECT_ID}"
echo " State:   gs://${CENTRAL_BUCKET}/${DEV_STATE_PREFIX}/"
echo "============================================"
```

Stan Terraform dla środowiska dev przechowywany jest pod ścieżką np. `gs://reinventor-terraform-states/ai-gateway-poc-qkhv/dev/`.

### 6. Etap 1/4 – Terraform apply (infrastruktura)

```bash
cd "${ROOT_DIR}/terraform/environments/dev"

terraform init -reconfigure \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${DEV_STATE_PREFIX}"

terraform apply -auto-approve \
  -var="project_id=${PROJECT_ID}"
```

Terraform tworzy infrastrukturę GCP:

- **VPC** – sieć prywatna
- **GKE** – klaster Kubernetes (zonal, 1 node `e2-standard-2`)
- **Service Account** dla LiteLLM z uprawnieniami Workload Identity

Flaga `-auto-approve` pomija pytanie o potwierdzenie (w przeciwieństwie do `create-project.sh` i `bootstrap.sh`, które pytają o `yes`).

Po apply skrypt pobiera adres konta serwisowego LiteLLM:

```bash
LITELLM_SA=$(terraform output -raw litellm_sa_email 2>/dev/null)
```

### 7. Etap 2/4 – Konfiguracja kubectl

```bash
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null)
CLUSTER_LOCATION=$(terraform output -raw cluster_location 2>/dev/null)

gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --zone "$CLUSTER_LOCATION" \
  --project "$PROJECT_ID"
```

Pobiera dane dostępowe do klastra GKE i konfiguruje `kubectl`:

- `CLUSTER_NAME` i `CLUSTER_LOCATION` – odczytane z outputów Terraform
- `gcloud container clusters get-credentials` – konfiguruje plik `~/.kube/config` z certyfikatem i endpointem klastra

Po tym kroku `kubectl` wskazuje na nowo utworzony klaster.

### 8. Etap 3/4 – Deploy mock backend

```bash
gcloud auth configure-docker "${AR_REGION}-docker.pkg.dev" --quiet

docker pull python:3.11-alpine

MOCK_IMAGE="$(ar_image mock-backend):latest"
cd "$ROOT_DIR/mock"

docker build -t "$MOCK_IMAGE" .
docker push "$MOCK_IMAGE"

sed "s|image: mock-backend:latest|image: ${MOCK_IMAGE}|" \
  k8s.yaml | kubectl apply -f -

kubectl rollout status deployment/mock-backend --timeout=120s
```

Mock backend to prosty serwer HTTP symulujący odpowiedzi LLM. Etap obejmuje:

0. **gcloud auth configure-docker** – konfiguruje Docker credentials dla Artifact Registry w regionie projektu
1. **docker pull python:3.11-alpine** – pobiera obraz bazowy z widocznym postępem (unika długiego oczekiwania podczas buildu)
2. **docker build** – buduje obraz kontenera z katalogu `mock/` (używa lekkiego Alpine zamiast Debian slim)
3. **docker push** – wysyła obraz do Artifact Registry w projekcie
4. **sed + kubectl apply** – modyfikuje manifest Kubernetes (`k8s.yaml`), podmieniając nazwę obrazu na pełną ścieżkę GCR, i wdraża na klaster
5. **kubectl rollout status** – czeka aż deployment będzie gotowy (timeout 120 sekund)

### 9. Etap 4/4 – Helm install LiteLLM

```bash
cd "$ROOT_DIR"

helm upgrade --install litellm oci://ghcr.io/berriai/litellm-helm \
  -f helm/values/litellm-dev.yaml \
  --set "serviceAccount.annotations.iam\.gke\.io/gcp-service-account=${LITELLM_SA}" \
  --wait \
  --timeout 5m
```

Instalacja LiteLLM – bramki AI – za pomocą Helm chart:

- `helm upgrade --install` – instaluje chart lub aktualizuje istniejący
- `oci://ghcr.io/berriai/litellm-helm` – chart pobierany z GitHub Container Registry jako artefakt OCI
- `-f helm/values/litellm-dev.yaml` – plik z konfiguracją deweloperską (modele, zasoby, baza danych)
- `--set "serviceAccount.annotations..."` – przypisuje konto serwisowe GCP do poda LiteLLM (Workload Identity)
- `--wait` – czeka aż wszystkie pody będą gotowe
- `--timeout 5m` – timeout 5 minut

### 10. Podsumowanie końcowe

```bash
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
```

Skrypt wyświetla:

- **Master Key** – klucz API do autoryzacji requestów
- **Port-forward** – komenda do tunelowania portu LiteLLM na localhost
- **Komendy testowe** – gotowe do skopiowania polecenia `curl` do weryfikacji

## Schemat przepływu

```
Użytkownik uruchamia skrypt
        │
        ▼
Załadowanie konfiguracji + wykrywanie projektu
        │
        ▼
Sprawdzenie: terraform, gcloud, kubectl, helm, docker?
        │ BRAK → błąd, koniec
        ▼ OK
[1/4] Terraform apply – infrastruktura (VPC, GKE, SA)
        │ BŁĄD → koniec
        ▼ OK
[2/4] gcloud get-credentials – konfiguracja kubectl
        │ BŁĄD → koniec
        ▼ OK
[3/4] Docker build + push + kubectl apply – mock backend
        │ BŁĄD → koniec
        ▼ OK
[4/4] Helm install – LiteLLM
        │ BŁĄD → koniec
        ▼ OK
Gotowe – środowisko działa
```

## Kolejność w cyklu życia projektu

```
create-project.sh  →  bootstrap.sh  →  up.sh  →  ... →  down.sh  →  destroy-project.sh
                                        ^^^^^
                                        JESTEŚ TUTAJ
```
