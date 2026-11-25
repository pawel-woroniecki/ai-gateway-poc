# bootstrap.sh – opis działania

Dokument wyjaśnia krok po kroku co robi skrypt `bootstrap.sh`, który inicjalizuje projekt GCP – włącza potrzebne API i tworzy konto serwisowe Terraform.

## Cel skryptu

Po utworzeniu projektu GCP (przez `create-project.sh`) sam projekt jest pusty – nie ma w nim włączonych usług ani uprawnień. `bootstrap.sh` przygotowuje projekt do pracy:

- włącza wymagane API Google Cloud (Kubernetes Engine, Compute, Container Registry itd.)
- tworzy **konto serwisowe** (Service Account) dla Terraform z odpowiednimi uprawnieniami
- konfiguruje IAM (Identity and Access Management)

## Sposób uruchomienia

```
./scripts/bootstrap.sh           # odczyt projektu z .project-env
./scripts/bootstrap.sh qkhv      # podany suffix projektu
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
check_requirements
```

- Ładuje wspólną konfigurację z `_config.sh`
- `auto_detect_project "${1:-}"` – wykrywa, na jakim projekcie pracować:
  - jeśli podano argument (np. `qkhv`) – używa go
  - jeśli nie – czyta z pliku `.project-env`
- Sprawdza, czy `terraform` i `gcloud` są zainstalowane

### 3. Walidacja zmiennych

```bash
: "${PROJECT_ID:?Ustaw zmienną PROJECT_ID lub najpierw uruchom create-project.sh}"
: "${SUFFIX:?Ustaw zmienną SUFFIX lub najpierw uruchom create-project.sh}"
REGION="${REGION:-europe-central2}"
```

Sprawdzenie, czy `PROJECT_ID` i `SUFFIX` są ustawione. Jeśli nie – wyświetla komunikat błędu i przerywa. Region domyślnie ustawiony na `europe-central2` (Warszawa).

### 4. Budowanie prefiksu state i wyświetlenie podsumowania

```bash
BOOTSTRAP_PREFIX=$(state_prefix "bootstrap")

echo "=== AI Gateway PoC – Bootstrap ==="
echo "Project:  ${PROJECT_ID}"
echo "Suffix:   ${SUFFIX}"
echo "Region:   ${REGION}"
echo "State:    gs://${CENTRAL_BUCKET}/${BOOTSTRAP_PREFIX}/"
```

Stan Terraform dla bootstrapu przechowywany jest pod ścieżką np. `gs://reinventor-terraform-states/ai-gateway-poc-qkhv/bootstrap/`.

### 5. Przełączenie kontekstu gcloud

```bash
gcloud config set project "${PROJECT_ID}"
```

Upewnia się, że `gcloud` wskazuje na właściwy projekt. Ważne, bo Terraform używa kontekstu gcloud do autoryzacji.

### 6. Terraform init – inicjalizacja

```bash
cd "${ROOT_DIR}/terraform/bootstrap"

terraform init -reconfigure \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${BOOTSTRAP_PREFIX}" \
  -input=false
```

Inicjalizacja Terraform z remote backend w GCS. Wchodzi do katalogu `terraform/bootstrap/`, gdzie znajduje się konfiguracja Terraform definiująca zasoby bootstrapowe.

- `-reconfigure` – wymusza ponowną konfigurację backendu (konieczne przy przełączaniu między projektami)
- `-backend-config` – dynamicznie podaje bucket i prefix
- `-input=false` – nie pyta interaktywnie

### 7. Terraform apply – tworzenie zasobów

```bash
terraform apply \
  -var="project_id=${PROJECT_ID}" \
  -var="region=${REGION}"
```

Terraform tworzy zasoby bootstrap w projekcie GCP. Typowe zasoby tworzone na tym etapie:

- włączenie API: Kubernetes Engine, Compute, Container Registry, IAM itd.
- konto serwisowe Terraform (`ai-gateway-terraform@...`) z uprawnieniami do zarządzania infrastrukturą
- bindingi IAM przypisujące role do konta serwisowego

Terraform wyświetla plan zmian i czeka na potwierdzenie użytkownika (`yes`).

### 8. Pobranie outputów

```bash
SA_EMAIL=$(terraform output -raw terraform_sa_email 2>/dev/null) || true

if [ -z "$SA_EMAIL" ]; then
  echo "BŁĄD: Nie udało się pobrać terraform_sa_email z outputów." >&2
  exit 1
fi
```

Po utworzeniu zasobów skrypt odczytuje adres e-mail konta serwisowego z outputów Terraform. `|| true` zapobiega przerwaniu skryptu przy błędzie komendy – walidacja następuje w kolejnym `if`.

### 9. Podsumowanie końcowe

```bash
echo "=== Bootstrap zakończony ==="
echo "Terraform SA: ${SA_EMAIL}"
echo ""
echo "Następny krok:"
echo "  ./scripts/up.sh"
```

Wyświetla adres konta serwisowego i wskazuje kolejny krok.

## Schemat przepływu

```
Użytkownik uruchamia skrypt
        │
        ▼
Załadowanie konfiguracji (_config.sh)
        │
        ▼
Auto-detekcja projektu (argument lub .project-env)
        │
        ▼
Sprawdzenie: terraform, gcloud zainstalowane?
        │ NIE → błąd, koniec
        ▼ TAK
Sprawdzenie: PROJECT_ID i SUFFIX ustawione?
        │ NIE → błąd, koniec
        ▼ TAK
Przełączenie kontekstu gcloud na projekt
        │
        ▼
Terraform init (remote backend w GCS – prefix: .../bootstrap)
        │ BŁĄD → koniec
        ▼ OK
Terraform apply (włączenie API, utworzenie SA, konfiguracja IAM)
        │ BŁĄD → koniec
        ▼ OK
Pobranie adresu SA z outputów Terraform
        │
        ▼
Gotowe – następny krok: up.sh
```

## Kolejność w cyklu życia projektu

```
create-project.sh  →  bootstrap.sh  →  up.sh  →  ... →  down.sh  →  destroy-project.sh
                       ^^^^^^^^^^^
                       JESTEŚ TUTAJ
```
