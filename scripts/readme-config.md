# _config.sh – opis działania

Dokument wyjaśnia krok po kroku co robi plik konfiguracyjny `_config.sh`, który jest współdzielony przez wszystkie skrypty AI Gateway PoC.

## Cel pliku

`_config.sh` nie jest uruchamiany samodzielnie – jest **ładowany** (sourcowany) przez pozostałe skrypty. Dostarcza im:

- stałe konfiguracyjne (nazwy, ścieżki, konto billingowe)
- funkcje pomocnicze (generowanie prefiksu state, sprawdzanie wymagań, auto-detekcja projektu, port-forward)

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

### 6. AR_REGION i funkcja `ar_image()`

```bash
AR_REGION="${AR_REGION:-europe-central2}"
```

Region Artifact Registry – musi być zgodny z `var.region` w Terraform. Domyślnie `europe-central2` (Warszawa). Można nadpisać zmienną środowiskową.

```bash
ar_image() {
  local image_name="$1"
  echo "${AR_REGION}-docker.pkg.dev/${PROJECT_ID}/ai-gateway/${image_name}"
}
```

Buduje pełną ścieżkę obrazu Docker w Artifact Registry. Skrypty `up.sh` i `down.sh` używają jej zamiast bezpośredniego adresu – wystarczy podać nazwę obrazu:

```bash
ar_image "mock-backend"
# → europe-central2-docker.pkg.dev/reinventor-ai-gateway-poc-abcd/ai-gateway/mock-backend
```

Repozytorium `ai-gateway` jest tworzone automatycznie przez Terraform w module dev.

### 7. Funkcja `find_free_port()` – znajdowanie wolnego portu

```bash
find_free_port() {
  local port="${1:-4000}"
  local max_attempts=20
  for (( i=0; i<max_attempts; i++ )); do
    if ! (echo >/dev/tcp/127.0.0.1/$port) 2>/dev/null; then
      echo "$port"
      return 0
    fi
    port=$((port + 1))
  done
  echo "BŁĄD: Nie znaleziono wolnego portu w zakresie ${1}–$((${1}+max_attempts-1))" >&2
  return 1
}
```

Sprawdza czy podany port jest wolny, a jeśli nie – szuka kolejnego. Mechanizm:

- Zaczyna od portu podanego jako argument (domyślnie 4000)
- Próbuje połączyć się z `127.0.0.1:port` przez bash `/dev/tcp`
- Jeśli połączenie się nie udaje (port wolny) – zwraca numer portu
- Jeśli port zajęty – próbuje kolejny (do 20 prób)

Cloud Shell nie ma narzędzia `lsof`, dlatego test portu opiera się na wbudowanym mechanizmie `/dev/tcp` basha.

**Przykład użycia:**

```bash
LOCAL_PORT=$(find_free_port 4000)
# → 4000 (jeśli wolny) lub 4001, 4002... (jeśli zajęte)
```

### 8. Funkcja `start_port_forward()` – uruchomienie port-forward

```bash
start_port_forward() {
  local deploy_name="$1"
  local target_port="${2:-4000}"
  local base_port="${3:-$target_port}"

  pkill -f "port-forward" 2>/dev/null || true
  sleep 1

  kubectl rollout status "deploy/${deploy_name}" --timeout=120s

  PF_PORT=$(find_free_port "$base_port")
  kubectl port-forward "deploy/${deploy_name}" "${PF_PORT}:${target_port}" &
  PF_PID=$!
  sleep 2

  if ! kill -0 "$PF_PID" 2>/dev/null; then
    echo "BŁĄD: Port-forward nie wystartował." >&2
    return 1
  fi
}
```

Uruchamia port-forward na wolnym porcie do wskazanego deploymentu. Wykonuje kolejno:

1. **Ubija istniejące port-forwardy** – `pkill -f "port-forward"` zamyka ewentualne pozostałości z poprzedniej sesji
2. **Czeka na deployment** – `kubectl rollout status` upewnia się, że pod jest gotowy (timeout 120s)
3. **Znajduje wolny port** – wywołuje `find_free_port` z bazowym portem
4. **Uruchamia port-forward w tle** – operator `&` uruchamia proces w tle
5. **Weryfikuje** – `kill -0` sprawdza czy proces jeszcze żyje po 2 sekundach

Funkcja ustawia dwie zmienne dostępne dla skryptu wywołującego:

| Zmienna | Opis |
|---|---|
| `PF_PORT` | Wybrany port lokalny (np. 4000) |
| `PF_PID` | PID procesu port-forward (do ewentualnego zatrzymania) |

**Przykład użycia (z `up.sh`):**

```bash
start_port_forward "litellm" 4000
echo "Port-forward: localhost:${PF_PORT} → deploy/litellm:4000 (PID: ${PF_PID})"
```

## Schemat zależności

```
_config.sh
    │
    ├── Stałe: BILLING_ACCOUNT, PROJECT_NAME_BASE, CENTRAL_BUCKET, AR_REGION, ...
    │
    ├── state_prefix()        ← używana przez wszystkie skrypty
    │
    ├── ar_image()            ← używana przez up.sh, down.sh
    │
    ├── check_requirements()  ← używana przez wszystkie skrypty
    │
    ├── auto_detect_project() ← używana przez bootstrap.sh, up.sh,
    │                            down.sh, destroy-project.sh
    │
    ├── find_free_port()      ← używana przez start_port_forward()
    │
    └── start_port_forward()  ← używana przez up.sh
```

## Powiązanie z innymi skryptami

Każdy skrypt w katalogu `scripts/` ładuje `_config.sh` jako pierwszą czynność po ustawieniu trybu bezpiecznego (`set -euo pipefail`).
