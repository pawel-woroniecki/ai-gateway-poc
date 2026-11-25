# down.sh – opis działania

Dokument wyjaśnia krok po kroku co robi skrypt `down.sh`, który usuwa środowisko deweloperskie (infrastrukturę), ale **zachowuje projekt GCP**.

## Cel skryptu

`down.sh` jest odwrotnością `up.sh` – usuwa zasoby deweloperskie w kolejności odwrotnej do tworzenia:

1. Sprawdza czy klaster GKE istnieje (optymalizacja – pomija Helm/kubectl gdy brak klastra)
2. Ubija aktywne port-forwardy
3. Odinstalowuje LiteLLM (Helm) z namespace `litellm`
4. Usuwa zasoby Kubernetes (mock backend)
5. Usuwa obraz kontenera z Artifact Registry
6. Niszczy infrastrukturę Terraform (klaster GKE, VPC, konta serwisowe)

**Projekt GCP pozostaje** – można ponownie uruchomić `up.sh` bez konieczności powtarzania `create-project.sh` i `bootstrap.sh`.

## Sposób uruchomienia

```
./scripts/down.sh           # odczyt projektu z .project-env
./scripts/down.sh qkhv      # podany suffix projektu
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

Ładuje wspólną konfigurację i wykrywa projekt.

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

Wymaga: `terraform`, `gcloud`, `kubectl`, `helm`. Docker nie jest potrzebny (nic nie jest budowane).

### 4. Walidacja zmiennych i podsumowanie

```bash
: "${PROJECT_ID:?Ustaw zmienną PROJECT_ID lub najpierw uruchom create-project.sh}"
: "${SUFFIX:?Ustaw zmienną SUFFIX lub najpierw uruchom create-project.sh}"
REGION="${REGION:-europe-central2}"
ZONE="${ZONE:-europe-central2-a}"

DEV_STATE_PREFIX=$(state_prefix "dev")
```

Sprawdzenie wymaganych zmiennych. Region i strefa domyślnie: `europe-central2` / `europe-central2-a`.

### 5. Potwierdzenie użytkownika

```bash
echo " UWAGA: To usunie wszystkie zasoby!"
read -p "Kontynuować? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Anulowano."
  exit 0
fi
```

Skrypt pyta o potwierdzenie przed usunięciem. Domyślna odpowiedź to **N** (nie) – trzeba jawnie wpisać `y` lub `Y`.

### 6. Etap 0/5 – Sprawdzenie klastra GKE

```bash
CLUSTER_NAME="ai-gateway-poc"
GKE_EXISTS=false

if gcloud container clusters describe "$CLUSTER_NAME" \
     --zone="$ZONE" --project="$PROJECT_ID" \
     --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
  GKE_EXISTS=true
  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone="$ZONE" --project="$PROJECT_ID" --quiet
else
  echo "  Klaster nie istnieje – pomijam kroki Helm/kubectl (2–3)."
fi
```

**Optymalizacja wydajności:** Skrypt sprawdza czy klaster GKE istnieje zanim spróbuje wykonywać komendy Helm i kubectl. Komenda `gcloud container clusters describe` wykonuje się w ~2 sekundy, podczas gdy kubectl/helm na nieistniejącym klastrze generowałyby ~60 sekund timeoutów.

Jeśli klaster istnieje:
- Ustawia flagę `GKE_EXISTS=true`
- Pobiera credentials kubectl

Jeśli klaster nie istnieje:
- Kroki 2 i 3 (Helm/kubectl) zostaną pominięte

### 7. Etap 1/5 – Ubijanie port-forwardów

```bash
pkill -f "port-forward" 2>/dev/null || true
```

Ubija wszystkie aktywne procesy port-forward uruchomione przez `up.sh`.

### 8. Etap 2/5 – Helm uninstall (warunkowo)

```bash
if $GKE_EXISTS; then
  helm uninstall litellm -n litellm 2>/dev/null || echo "  (nie znaleziono release)"
fi
```

Odinstalowuje release Helm `litellm` z namespace `litellm`. Flaga `-n litellm` jest konieczna, ponieważ LiteLLM jest instalowany w dedykowanym namespace.

**Wykonuje się tylko gdy klaster GKE istnieje** (`GKE_EXISTS=true`). Jeśli release nie istnieje (już usunięty), wyświetla informację i kontynuuje.

### 9. Etap 3/5 – Usuwanie zasobów Kubernetes (warunkowo)

```bash
if $GKE_EXISTS; then
  kubectl delete -f "$ROOT_DIR/k8s/mock-backend.yaml" 2>/dev/null \
    || echo "  (mock-backend nie znaleziony)"
fi
```

Usuwa **mock backend** – deployment i service zdefiniowane w `k8s/mock-backend.yaml`.

**Wykonuje się tylko gdy klaster GKE istnieje.** Polecenie ma `|| echo "..."`, dzięki czemu brak danego zasobu nie przerywa skryptu.

### 10. Etap 4/5 – Usuwanie obrazu z Artifact Registry

```bash
MOCK_IMAGE="$(ar_image mock-backend):latest"
gcloud artifacts docker images delete "$MOCK_IMAGE" \
  --delete-tags --quiet 2>/dev/null \
  || echo "  (obraz nie znaleziony lub registry nie istnieje)"
```

Usuwa obraz Docker mock backendu z Artifact Registry:

- `--delete-tags` – usuwa wszystkie tagi obrazu
- `--quiet` – nie pyta o potwierdzenie

Ten krok wykonuje się niezależnie od istnienia klastra GKE, ponieważ Artifact Registry jest zasobem na poziomie projektu.

### 11. Etap 5/5 – Terraform destroy

```bash
cd "$ROOT_DIR/terraform/environments/dev"

terraform init -reconfigure \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${DEV_STATE_PREFIX}" \
  -input=false

terraform destroy \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}" \
  -var="zone=${ZONE}" \
  -auto-approve
```

Niszczy infrastrukturę GCP utworzoną przez `up.sh`:

1. **terraform init** – inicjalizacja z remote backend (prefix `.../dev`)
2. **terraform destroy** – usunięcie wszystkich zasobów:
   - klaster GKE
   - sieć VPC i podsieci
   - konta serwisowe
   - reguły firewalla

Flaga `-auto-approve` pomija pytanie o potwierdzenie (użytkownik już potwierdził na początku skryptu). Oba kroki używają obsługi błędów (`if !`) – jeśli terraform init lub destroy się nie powiedzie, skrypt przerywa działanie z komunikatem błędu.

### 12. Podsumowanie końcowe

```bash
echo " AI Gateway PoC – USUNIĘTE"
echo ""
echo " Aby usunąć również cały projekt GCP:"
echo "   ./scripts/destroy-project.sh"
```

Informuje, że środowisko zostało usunięte i wskazuje kolejny krok – jeśli użytkownik chce usunąć również sam projekt GCP.

## Schemat przepływu

```
Użytkownik uruchamia skrypt
        │
        ▼
Załadowanie konfiguracji + wykrywanie projektu
        │
        ▼
Sprawdzenie wymagań (terraform, gcloud, kubectl, helm)
        │ BRAK → błąd, koniec
        ▼ OK
Potwierdzenie użytkownika: "Kontynuować? (y/N)"
        │ N → anulowano, koniec
        ▼ y
[0/5] Sprawdzenie klastra GKE (~2s)
        │
        ├── GKE istnieje → GKE_EXISTS=true, pobranie credentials
        │
        └── GKE nie istnieje → GKE_EXISTS=false
                                (kroki 2–3 pominięte)
        ▼
[1/5] Ubijanie port-forwardów
        │
        ▼
[2/5] Helm uninstall – LiteLLM (namespace: litellm)
        │ (pominięto jeśli GKE_EXISTS=false)
        ▼
[3/5] kubectl delete – mock backend (k8s/mock-backend.yaml)
        │ (pominięto jeśli GKE_EXISTS=false)
        ▼
[4/5] gcloud – usunięcie obrazu z Artifact Registry
        │ (kontynuuje nawet jeśli nie znaleziono)
        ▼
[5/5] Terraform destroy – infrastruktura (GKE, VPC, SA)
        │ BŁĄD → koniec
        ▼ OK
Gotowe – projekt GCP nadal istnieje
```

## Kolejność w cyklu życia projektu

```
create-project.sh  →  bootstrap.sh  →  up.sh  →  ... →  down.sh  →  destroy-project.sh
                                                          ^^^^^^^
                                                          JESTEŚ TUTAJ
```

## Różnica między down.sh a destroy-project.sh

| Skrypt | Co usuwa | Co zostaje |
|---|---|---|
| `down.sh` | Infrastruktura dev (GKE, VPC, mock, LiteLLM) | Projekt GCP, bootstrap (API, SA), state w GCS |
| `destroy-project.sh` | Projekt GCP + wszystkie stany w GCS | Nic – pełne czyszczenie |

Typowy scenariusz: `down.sh` na koniec dnia pracy (oszczędność kosztów), `up.sh` rano. `destroy-project.sh` gdy PoC zakończony.
