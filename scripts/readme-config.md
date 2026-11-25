# _config.sh – opis działania

Dokument wyjaśnia krok po kroku co robi plik konfiguracyjny `_config.sh`, który jest współdzielony przez wszystkie skrypty AI Gateway PoC.

## Cel pliku

`_config.sh` nie jest uruchamiany samodzielnie – jest **ładowany** (sourcowany) przez pozostałe skrypty. Dostarcza im:

- stałe konfiguracyjne (nazwy, ścieżki, konto billingowe)
- funkcje pomocnicze (generowanie prefiksu state, sprawdzanie wymagań, auto-detekcja projektu)

Dzięki centralizacji konfiguracji zmiana np. nazwy bucketa wymaga edycji tylko jednego pliku.

## Sposób użycia (w innych skryptach)

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"
```

## Elementy pliku

### 1. Stałe konfiguracyjne

```bash
BILLING_ACCOUNT="${BILLING_ACCOUNT:-017C3F-481026-534AC8}"
PROJECT_NAME_BASE="reinventor-ai-gateway-poc"
CENTRAL_BUCKET="reinventor-terraform-states"
STATE_PREFIX_BASE="ai-gateway-poc"
```

| Stała | Wartość | Opis |
|---|---|---|
| `BILLING_ACCOUNT` | `017C3F-481026-534AC8` | Konto rozliczeniowe GCP. Konstrukcja `${VAR:-default}` oznacza: użyj wartości zmiennej środowiskowej, a jeśli nie jest ustawiona – użyj wartości domyślnej. Pozwala to nadpisać konto przez `export BILLING_ACCOUNT="..."` |
| `PROJECT_NAME_BASE` | `reinventor-ai-gateway-poc` | Bazowa nazwa projektu GCP. Suffix (4 litery) doklejany jest na końcu, dając np. `reinventor-ai-gateway-poc-qkhv` |
| `CENTRAL_BUCKET` | `reinventor-terraform-states` | Nazwa bucketa GCS przechowującego stany Terraform. Bucket znajduje się w **osobnym** projekcie GCP |
| `STATE_PREFIX_BASE` | `ai-gateway-poc` | Bazowy prefix ścieżki w buckecie. Suffix dodawany dynamicznie |

### 2. Ścieżki katalogów

```bash
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_TF_DIR="${ROOT_DIR}/terraform/project"
```

| Zmienna | Opis |
|---|---|
| `ROOT_DIR` | Katalog główny repozytorium (rodzic katalogu `scripts/`) |
| `PROJECT_TF_DIR` | Katalog z konfiguracją Terraform do tworzenia projektu GCP |

`SCRIPT_DIR` musi być ustawiony przez skrypt wywołujący **przed** załadowaniem `_config.sh`.

### 3. Funkcja `state_prefix()` – budowanie prefiksu state w GCS

```bash
state_prefix() {
  local module="$1"
  echo "${STATE_PREFIX_BASE}-${SUFFIX}/${module}"
}
```

Funkcja łączy bazowy prefix, suffix projektu i nazwę modułu w pełną ścieżkę w buckecie GCS.

**Przykłady wywołania:**

| Wywołanie | Wynik (przy SUFFIX=qkhv) | Pełna ścieżka GCS |
|---|---|---|
| `state_prefix "project"` | `ai-gateway-poc-qkhv/project` | `gs://reinventor-terraform-states/ai-gateway-poc-qkhv/project` |
| `state_prefix "bootstrap"` | `ai-gateway-poc-qkhv/bootstrap` | `gs://reinventor-terraform-states/ai-gateway-poc-qkhv/bootstrap` |
| `state_prefix "dev"` | `ai-gateway-poc-qkhv/dev` | `gs://reinventor-terraform-states/ai-gateway-poc-qkhv/dev` |

Dzięki temu każdy projekt (identyfikowany suffixem) ma **trzy niezależne stany Terraform** i wiele projektów może współistnieć równolegle.

### 4. Funkcja `check_requirements()` – sprawdzenie wymaganych narzędzi

```bash
check_requirements() {
  local missing=()
  command -v terraform >/dev/null 2>&1 || missing+=("terraform")
  command -v gcloud >/dev/null 2>&1    || missing+=("gcloud")

  if [ ${#missing[@]} -gt 0 ]; then
    echo "BŁĄD: Brakujące narzędzia: ${missing[*]}" >&2
    exit 1
  fi
}
```

Funkcja sprawdza, czy na maszynie zainstalowane są:

- **terraform** – narzędzie Infrastructure as Code
- **gcloud** – CLI Google Cloud

Mechanizm:

- `command -v <nazwa>` sprawdza, czy komenda jest dostępna w systemie
- `>/dev/null 2>&1` – ukrywa output (interesuje nas tylko kod powrotu)
- `|| missing+=(...)` – jeśli komenda nie znaleziona, dodaje ją do tablicy brakujących
- `${#missing[@]}` – sprawdza liczbę elementów w tablicy
- jeśli coś brakuje, wyświetla komunikat błędu na stderr (`>&2`) i przerywa skrypt

### 5. Funkcja `auto_detect_project()` – automatyczne wykrywanie projektu

```bash
auto_detect_project() {
  # Jeśli podano argument – użyj go
  if [ -n "${1:-}" ]; then
    SUFFIX="$1"
    PROJECT_ID="${PROJECT_NAME_BASE}-${SUFFIX}"
    echo ">>> Użycie suffixu z argumentu: ${SUFFIX}"
    return
  fi

  # Fallback: odczyt z .project-env
  if [ -z "${PROJECT_ID:-}" ] && [ -f "${ROOT_DIR}/.project-env" ]; then
    echo ">>> Odczytywanie PROJECT_ID z .project-env..."
    source "${ROOT_DIR}/.project-env"
  fi
}
```

Funkcja ustawia zmienne `SUFFIX` i `PROJECT_ID` na podstawie jednego z dwóch źródeł:

**Priorytet 1 – argument wiersza poleceń:**

Jeśli skrypt został wywołany z argumentem (np. `./scripts/bootstrap.sh qkhv`), suffix jest brany z tego argumentu. `PROJECT_ID` jest budowany automatycznie: `reinventor-ai-gateway-poc-qkhv`.

**Priorytet 2 – plik `.project-env`:**

Jeśli argument nie został podany i `PROJECT_ID` nie jest jeszcze ustawiony, funkcja szuka pliku `.project-env` w katalogu głównym repozytorium. Plik ten jest tworzony automatycznie przez `create-project.sh`.

Dzięki temu:

- po uruchomieniu `create-project.sh` wszystkie kolejne skrypty automatycznie wiedzą, na jakim projekcie pracują
- podanie suffixu jako argumentu pozwala operować na **dowolnym** projekcie, niezależnie od tego, co jest w `.project-env`

## Schemat zależności

```
_config.sh
    │
    ├── Stałe: BILLING_ACCOUNT, PROJECT_NAME_BASE, CENTRAL_BUCKET, ...
    │
    ├── state_prefix()       ← używana przez wszystkie skrypty
    │
    ├── check_requirements() ← używana przez wszystkie skrypty
    │
    └── auto_detect_project() ← używana przez bootstrap.sh, up.sh,
                                 down.sh, destroy-project.sh
```

## Powiązanie z innymi skryptami

Każdy skrypt w katalogu `scripts/` ładuje `_config.sh` jako pierwszą czynność po ustawieniu trybu bezpiecznego (`set -euo pipefail`).
