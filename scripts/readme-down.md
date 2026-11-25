# down.sh – opis działania

Dokument wyjaśnia krok po kroku co robi skrypt `down.sh`, który usuwa środowisko deweloperskie (infrastrukturę), ale **zachowuje projekt GCP**.

## Cel skryptu

`down.sh` jest odwrotnością `up.sh` – usuwa zasoby deweloperskie w kolejności odwrotnej do tworzenia:

1. Odinstalowuje LiteLLM (Helm)
2. Usuwa zasoby Kubernetes (mock backend, sekrety, configmapy)
3. Usuwa obraz kontenera z Google Container Registry
4. Niszczy infrastrukturę Terraform (klaster GKE, VPC, konta serwisowe)

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

### 6. Etap 1/4 – Helm uninstall

```bash
helm uninstall litellm 2>/dev/null || echo "  (nie znaleziono release)"
```

Odinstalowuje release Helm `litellm`. Jeśli release nie istnieje (już usunięty), wyświetla informację i kontynuuje – `|| echo "..."` zapobiega przerwaniu skryptu.

### 7. Etap 2/4 – Usuwanie zasobów Kubernetes

```bash
kubectl delete -f "$ROOT_DIR/mock/k8s.yaml" 2>/dev/null || echo "  (mock-backend nie znaleziony)"
kubectl delete secret litellm-secrets litellm-env 2>/dev/null || true
kubectl delete configmap litellm-config 2>/dev/null || true
```

Usuwa:

- **mock backend** – deployment i service zdefiniowane w `mock/k8s.yaml`
- **sekrety** (`litellm-secrets`, `litellm-env`) – klucze API i zmienne środowiskowe
- **configmapy** (`litellm-config`) – konfiguracja LiteLLM

Każde polecenie ma `|| true` lub `|| echo "..."`, dzięki czemu brak danego zasobu nie przerywa skryptu.

### 8. Etap 3/4 – Usuwanie obrazu z GCR

```bash
gcloud container images delete "gcr.io/${PROJECT_ID}/mock-backend:latest" \
  --force-delete-tags --quiet 2>/dev/null || echo "  (obraz nie znaleziony)"
```

Usuwa obraz Docker mock backendu z Google Container Registry:

- `--force-delete-tags` – usuwa wszystkie tagi obrazu
- `--quiet` – nie pyta o potwierdzenie

### 9. Etap 4/4 – Terraform destroy

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

Flaga `-auto-approve` pomija pytanie o potwierdzenie (użytkownik już potwierdził na początku skryptu).

### 10. Podsumowanie końcowe

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
[1/4] Helm uninstall – LiteLLM
        │ (kontynuuje nawet jeśli nie znaleziono)
        ▼
[2/4] kubectl delete – mock backend, sekrety, configmapy
        │ (kontynuuje nawet jeśli nie znaleziono)
        ▼
[3/4] gcloud – usunięcie obrazu z GCR
        │ (kontynuuje nawet jeśli nie znaleziono)
        ▼
[4/4] Terraform destroy – infrastruktura (GKE, VPC, SA)
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
