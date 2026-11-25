# up.sh – opis działania

Dokument wyjaśnia krok po kroku co robi skrypt `up.sh`, który stawia pełne środowisko AI Gateway PoC – od infrastruktury po działającą aplikację.

## Cel skryptu

`up.sh` to główny skrypt uruchamiający środowisko. Wykonuje sześć etapów:

1. Tworzy infrastrukturę w GCP (klaster Kubernetes, sieć, konta serwisowe)
2. Konfiguruje dostęp do klastra (kubectl)
3. Buduje i wdraża mock backend (symulowany endpoint LLM)
4. Instaluje LiteLLM – bramkę AI (gateway)
5. Sprawdza migracje bazy danych (fallback: `prisma db push`)
6. Pobiera External IP LoadBalancera i uruchamia port-forward

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
for cmd in kubectl helm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "BŁĄD: Brak wymaganego narzędzia: $cmd" >&2
    exit 1
  fi
done
```

Oprócz standardowych `terraform` i `gcloud`, skrypt wymaga dodatkowych narzędzi:

- **kubectl** – CLI do zarządzania klastrem Kubernetes
- **helm** – menedżer pakietów Kubernetes (do instalacji LiteLLM)

Docker **nie jest wymagany** lokalnie – budowanie obrazu mock backendu odbywa się na serwerach Google (Cloud Build).

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

### 6. Etap 1/5 – Terraform apply (infrastruktura)

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

Flaga `-auto-approve` pomija pytanie o potwierdzenie. Oba kroki (init i apply) używają obsługi błędów (`if !`) – przy niepowodzeniu skrypt przerywa działanie.

Po apply skrypt pobiera adres konta serwisowego LiteLLM:

```bash
LITELLM_SA=$(terraform output -raw litellm_sa_email 2>/dev/null)
```

### 7. Etap 2/5 – Konfiguracja kubectl

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

### 8. Etap 3/5 – Deploy mock backend

```bash
MOCK_IMAGE="$(ar_image mock-backend):latest"
cd "$ROOT_DIR/mock"

gcloud builds submit \
  --tag "$MOCK_IMAGE" \
  --project "$PROJECT_ID" \
  --quiet

sed "s|image: mock-backend:latest|image: ${MOCK_IMAGE}|" \
  k8s.yaml | kubectl apply -f -

kubectl rollout status deployment/mock-backend --timeout=120s
```

Mock backend to prosty serwer HTTP symulujący odpowiedzi LLM. Etap obejmuje:

1. **gcloud builds submit** – wysyła kod do Cloud Build, który buduje obraz Docker i pushuje go do Artifact Registry. Build odbywa się na serwerach Google, nie wymaga lokalnego Dockera
2. **sed + kubectl apply** – modyfikuje manifest Kubernetes (`k8s.yaml`), podmieniając nazwę obrazu na pełną ścieżkę Artifact Registry, i wdraża na klaster
3. **kubectl rollout status** – czeka aż deployment będzie gotowy (timeout 120 sekund)

### 9. Etap 4/5 – Helm install LiteLLM

```bash
cd "$ROOT_DIR"

helm upgrade --install litellm oci://ghcr.io/berriai/litellm-helm \
  -f helm/values/litellm-dev.yaml \
  --set "serviceAccount.annotations.iam\.gke\.io/gcp-service-account=${LITELLM_SA}" \
  --wait \
  --timeout 8m
```

Instalacja LiteLLM – bramki AI – za pomocą Helm chart:

- `helm upgrade --install` – instaluje chart lub aktualizuje istniejący
- `oci://ghcr.io/berriai/litellm-helm` – chart pobierany z GitHub Container Registry jako artefakt OCI
- `-f helm/values/litellm-dev.yaml` – plik z konfiguracją deweloperską (modele, zasoby, baza danych)
- `--set "serviceAccount.annotations..."` – przypisuje konto serwisowe GCP do poda LiteLLM (Workload Identity)
- `--wait` – czeka aż wszystkie pody będą gotowe
- `--timeout 8m` – timeout 8 minut (zwiększony z domyślnych 5m ze względu na czas inicjalizacji PostgreSQL i migracji)

### 10. Etap 5/6 – Migracje bazy danych (fallback)

```bash
if ! kubectl exec deploy/litellm -- python3 -c "
import asyncio
from litellm.proxy.db.prisma_client import PrismaClient
pc = PrismaClient(database_url=None, proxy_logging_obj=None)
asyncio.run(pc.connect())
print('DB OK')
" 2>/dev/null | grep -q "DB OK"; then
  kubectl exec deploy/litellm -- sh -c '
    export DATABASE_URL="postgresql://litellm:litellm-poc-password@litellm-postgresql:5432/litellm"
    export DIRECT_URL="$DATABASE_URL"
    prisma db push --schema=/app/schema.prisma --accept-data-loss
  '
  kubectl rollout restart deployment/litellm
  kubectl rollout status deployment/litellm --timeout=180s
fi
```

Helm chart LiteLLM zawiera migrations job oparty na Prisma ORM. Czasem job ten failuje, gdy PostgreSQL nie jest jeszcze w pełni gotowy. Skrypt implementuje fallback:

1. **Sprawdzenie** – próbuje połączyć się z bazą danych z poda LiteLLM
2. **Jeśli tabele nie istnieją** – uruchamia `prisma db push` z explicite ustawionym `DATABASE_URL`
3. **Restart** – restartuje deployment LiteLLM i czeka na gotowość (timeout 180s)

Jeśli tabele istnieją – wyświetla "Tabele OK" i przechodzi dalej.

### 11. Etap 6/6 – External IP i port-forward

```bash
# Czekaj na External IP (max 2 min)
for i in $(seq 1 24); do
  EXTERNAL_IP=$(kubectl get svc litellm \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "<pending>" ]; then
    break
  fi
  sleep 5
done

start_port_forward "litellm" 4000
```

Etap końcowy przygotowuje dostęp do LiteLLM:

1. **External IP** – czeka na przydzielenie adresu IP przez LoadBalancer (max ~2 minuty, sprawdza co 5 sekund). LiteLLM jest wystawiony jako Service typu LoadBalancer, dzięki czemu Admin UI jest dostępny z przeglądarki (Cloud Shell Web Preview nie działa – stripuje nagłówki Set-Cookie)
2. **Port-forward** – funkcja `start_port_forward` z `_config.sh` uruchamia port-forward na wolnym porcie (domyślnie 4000, szuka kolejnych jeśli zajęty). Port-forward umożliwia dostęp do API LiteLLM z poziomu Cloud Shell via curl

### 12. Podsumowanie końcowe

```bash
echo " Master Key: sk-aigw-master-poc-dev"
echo ""
echo " LiteLLM Admin UI (przeglądarka):"
echo "   http://${EXTERNAL_IP}:4000/ui"
echo ""
echo " Port-forward (curl z Cloud Shell):"
echo "   localhost:${PF_PORT} → deploy/litellm:4000  (PID: ${PF_PID})"
echo ""
echo " Test:"
echo "   curl http://localhost:${PF_PORT}/health/liveliness"
```

Skrypt wyświetla:

- **Master Key** – klucz API do autoryzacji requestów
- **Admin UI URL** – adres zewnętrzny do LiteLLM Admin UI (jeśli External IP został przydzielony)
- **Port-forward** – wybrany port i PID procesu
- **Komendy testowe** – gotowe do skopiowania polecenia `curl` do weryfikacji
- **Referencja** do instrukcji UI (`instrukcje/06-litellm-admin-ui.md`)

## Schemat przepływu

```
Użytkownik uruchamia skrypt
        │
        ▼
Załadowanie konfiguracji + wykrywanie projektu
        │
        ▼
Sprawdzenie: terraform, gcloud, kubectl, helm?
        │ BRAK → błąd, koniec
        ▼ OK
[1/5] Terraform apply – infrastruktura (VPC, GKE, SA)
        │ BŁĄD → koniec
        ▼ OK
[2/5] gcloud get-credentials – konfiguracja kubectl
        │ BŁĄD → koniec
        ▼ OK
[3/5] Cloud Build + kubectl apply – mock backend
        │ BŁĄD → koniec
        ▼ OK
[4/5] Helm install – LiteLLM (timeout: 8m)
        │ BŁĄD → koniec
        ▼ OK
[5/6] Sprawdzenie migracji DB
        │
        ├── Tabele OK → kontynuuj
        │
        └── Brak tabel → prisma db push + restart deployment
        ▼
[6/6] External IP (max 2 min) + port-forward
        │
        ▼
Gotowe – środowisko działa
```

## Kolejność w cyklu życia projektu

```
create-project.sh  →  bootstrap.sh  →  up.sh  →  ... →  down.sh  →  destroy-project.sh
                                        ^^^^^
                                        JESTEŚ TUTAJ
```
