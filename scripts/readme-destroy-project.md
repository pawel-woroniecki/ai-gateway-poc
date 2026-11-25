# destroy-project.sh – opis działania

Dokument wyjaśnia krok po kroku co robi skrypt `destroy-project.sh`, który trwale usuwa projekt GCP i czyści wszystkie stany Terraform.

## Cel skryptu

`destroy-project.sh` to skrypt do **pełnego czyszczenia** – usuwa:

- projekt GCP wraz ze wszystkimi zasobami w nim (klaster, sieć, konta serwisowe, API)
- wszystkie trzy stany Terraform z bucketa GCS (project, bootstrap, dev)
- pliki lokalne (`.project-env`, `errored.tfstate`)

Po uruchomieniu tego skryptu nie pozostaje ślad po środowisku PoC. Dzięki unikalnemu suffixowi można natychmiast utworzyć nowy projekt.

## Sposób uruchomienia

```
./scripts/destroy-project.sh           # odczyt projektu z .project-env
./scripts/destroy-project.sh qkhv      # podany suffix projektu
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
check_requirements

: "${BILLING_ACCOUNT:?Ustaw zmienną BILLING_ACCOUNT, np. export BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX}"

ORG_ID="${ORG_ID:-}"
FOLDER_ID="${FOLDER_ID:-}"

auto_detect_project "${1:-}"
```

Ładuje konfigurację, sprawdza wymagania, waliduje konto billingowe (potrzebne dla zmiennych Terraform) i wykrywa projekt.

### 3. Walidacja suffixu

```bash
if [ -z "${SUFFIX:-}" ]; then
  echo "BŁĄD: Nie znaleziono SUFFIX. Podaj jako argument lub uruchom create-project.sh." >&2
  exit 1
fi
```

Suffix jest konieczny do identyfikacji projektu i ścieżek state w GCS.

### 4. Terraform init – inicjalizacja

```bash
PROJECT_STATE_PREFIX=$(state_prefix "project")
cd "$PROJECT_TF_DIR"

terraform init -reconfigure \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${PROJECT_STATE_PREFIX}" \
  -input=false
```

Inicjalizacja Terraform z remote backend wskazującym na state projektu (`ai-gateway-poc-XXXX/project`).

### 5. Sprawdzenie czy projekt istnieje w state

```bash
CURRENT_PROJECT=$(terraform output -raw project_id 2>/dev/null || echo "")

if [ -z "$CURRENT_PROJECT" ]; then
  echo "Brak projektu w remote state – nie ma czego usuwać."
  for prefix in \
    "$(state_prefix "project")" \
    "$(state_prefix "bootstrap")" \
    "$(state_prefix "dev")"; do
    gsutil -m rm -r "gs://${CENTRAL_BUCKET}/${prefix}/" 2>/dev/null || true
  done
  exit 0
fi
```

Skrypt sprawdza, czy w remote state Terraform jest zarejestrowany projekt. Jeśli nie (np. był już usunięty, ale zostały pliki state) – czyści state z GCS i kończy pracę.

Pętla `for prefix in ...` iteruje po trzech prefiksach (project, bootstrap, dev) i czyści każdy z nich.

### 6. Potwierdzenie użytkownika

```bash
echo " UWAGA: Zostanie TRWALE usunięty projekt:"
echo "   $CURRENT_PROJECT"
echo ""
echo " Ta operacja jest nieodwracalna!"
read -p " Kontynuować? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Anulowano."
  exit 0
fi
```

Wymaga wpisania pełnego słowa `yes` (nie tylko `y`) – dodatkowe zabezpieczenie przed przypadkowym usunięciem projektu.

### 7. Terraform destroy – usunięcie projektu

```bash
TF_VARS=(
  -var="billing_account=${BILLING_ACCOUNT}"
  -var="suffix=${SUFFIX}"
)
[ -n "$ORG_ID" ] && TF_VARS+=(-var="org_id=${ORG_ID}")
[ -n "$FOLDER_ID" ] && TF_VARS+=(-var="folder_id=${FOLDER_ID}")

DESTROY_EXIT=0
terraform destroy "${TF_VARS[@]}" || DESTROY_EXIT=$?

if [ $DESTROY_EXIT -ne 0 ]; then
  echo "UWAGA: terraform destroy zwrócił kod $DESTROY_EXIT."
  echo "Kontynuuję czyszczenie..."
fi
```

Terraform niszczy projekt GCP. Kluczowe elementy:

- **Tablica zmiennych** – te same zmienne co przy tworzeniu projektu (Terraform musi wiedzieć, jaki zasób usunąć)
- **Obsługa błędu bez przerwania** – konstrukcja `|| DESTROY_EXIT=$?` przechwytuje kod wyjścia zamiast przerywać skrypt. Terraform destroy może się częściowo nie powieść (np. gdy billing został wcześniej wyłączony), ale czyszczenie state powinno kontynuować

### 8. Czyszczenie stanów Terraform z GCS

```bash
for prefix in \
  "$(state_prefix "project")" \
  "$(state_prefix "bootstrap")" \
  "$(state_prefix "dev")"; do
  if gsutil -m rm -r "gs://${CENTRAL_BUCKET}/${prefix}/" 2>/dev/null; then
    echo "  Usunięto: gs://${CENTRAL_BUCKET}/${prefix}/"
  else
    echo "  Brak/już usunięte: ${prefix}"
  fi
done
```

Pętla usuwa **wszystkie trzy** stany Terraform z bucketa GCS:

| Prefix | Co przechowywał |
|---|---|
| `ai-gateway-poc-XXXX/project` | Stan projektu GCP (z `create-project.sh`) |
| `ai-gateway-poc-XXXX/bootstrap` | Stan bootstrapu – API, SA, IAM (z `bootstrap.sh`) |
| `ai-gateway-poc-XXXX/dev` | Stan infrastruktury dev – GKE, VPC (z `up.sh`) |

- `gsutil -m rm -r` – rekurencyjne usunięcie z wielowątkowym przetwarzaniem (`-m`)
- `2>/dev/null` – ukrywa błędy (jeśli prefix już nie istnieje)

### 9. Czyszczenie plików lokalnych

```bash
rm -f "${PROJECT_TF_DIR}/errored.tfstate"
rm -f "${PROJECT_TF_DIR}/errored.tfstate.backup"
rm -f "${ROOT_DIR}/.project-env"
```

Usuwa:

- `errored.tfstate` – plik awaryjny tworzony przez Terraform gdy zapis state do GCS się nie powiódł
- `.project-env` – plik z PROJECT_ID i SUFFIX (żeby następne uruchomienie skryptów nie próbowało operować na nieistniejącym projekcie)

### 10. Weryfikacja usunięcia

```bash
if gcloud projects describe "$CURRENT_PROJECT" >/dev/null 2>&1; then
  echo "UWAGA: Projekt $CURRENT_PROJECT nadal widoczny w GCP – usunięcie może potrwać kilka sekund."
else
  echo "  Projekt usunięty z GCP."
fi
```

Sprawdza przez `gcloud` czy projekt jest już niewidoczny. Propagacja usunięcia w GCP może trwać kilka sekund.

### 11. Podsumowanie końcowe

```bash
echo " Projekt $CURRENT_PROJECT usunięty."
echo " Plik .project-env usunięty."
echo " State GCS wyczyszczony."
echo ""
echo " Aby utworzyć nowy projekt:"
echo "   ./scripts/create-project.sh"
```

Potwierdza usunięcie i wskazuje, że można od razu utworzyć nowy projekt.

## Schemat przepływu

```
Użytkownik uruchamia skrypt
        │
        ▼
Załadowanie konfiguracji + wykrywanie projektu
        │
        ▼
Sprawdzenie wymagań + walidacja SUFFIX
        │ BRAK → błąd, koniec
        ▼ OK
Terraform init (remote backend – prefix: .../project)
        │
        ▼
Sprawdzenie: czy projekt istnieje w state?
        │ NIE → czyszczenie GCS, koniec
        ▼ TAK
Potwierdzenie użytkownika: "Kontynuować? (yes/no)"
        │ no → anulowano, koniec
        ▼ yes
Terraform destroy (usunięcie projektu GCP)
        │ BŁĄD → ostrzeżenie, kontynuuje czyszczenie
        ▼
Czyszczenie state z GCS (3 prefixy: project, bootstrap, dev)
        │
        ▼
Usunięcie plików lokalnych (.project-env, errored.tfstate)
        │
        ▼
Weryfikacja usunięcia projektu w GCP
        │
        ▼
Gotowe – można utworzyć nowy projekt
```

## Kolejność w cyklu życia projektu

```
create-project.sh  →  bootstrap.sh  →  up.sh  →  ... →  down.sh  →  destroy-project.sh
                                                                       ^^^^^^^^^^^^^^^^^^
                                                                       JESTEŚ TUTAJ
```

## Różnica między down.sh a destroy-project.sh

| Aspekt | down.sh | destroy-project.sh |
|---|---|---|
| Co usuwa | Infrastruktura dev (GKE, VPC, mock, LiteLLM) | Cały projekt GCP + wszystkie stany |
| Co zostaje | Projekt GCP, bootstrap, stany w GCS | Nic |
| Potwierdzenie | `y/N` | Pełne `yes/no` |
| `.project-env` | Zostaje | Usuwany |
| Kiedy używać | Koniec dnia pracy / oszczędność kosztów | Koniec PoC / pełne czyszczenie |
| Po wykonaniu | `up.sh` stawia środowisko od nowa | `create-project.sh` tworzy nowy projekt |
