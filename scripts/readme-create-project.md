# create-project.sh – opis działania

Dokument wyjaśnia krok po kroku co robi skrypt `create-project.sh`, który tworzy nowy projekt GCP na potrzeby środowiska AI Gateway PoC.

## Cel skryptu

Skrypt automatyzuje tworzenie nowego projektu Google Cloud Platform (GCP) z unikalną nazwą. Dzięki unikalnemu 4-literowemu suffixowi (np. `qkhv`, `pjbr`) możliwe jest:

- tworzenie wielu niezależnych środowisk równolegle
- natychmiastowe tworzenie nowego projektu po usunięciu starego (bez czekania 30 dni na permanentne usunięcie w GCP)

## Sposób uruchomienia

```
./scripts/create-project.sh           # losowy suffix
./scripts/create-project.sh abcd      # własny suffix (4 małe litery)
```

## Kroki realizowane przez skrypt

### 1. Tryb bezpieczny

Skrypt włącza tryb, w którym każdy błąd natychmiast przerywa wykonanie. Zapobiega to sytuacji, w której skrypt kontynuuje pracę po częściowej awarii.

```bash
set -euo pipefail
```

- `set -e` – przerwij przy pierwszym błędzie
- `set -u` – traktuj niezdefiniowane zmienne jako błąd
- `set -o pipefail` – błąd w dowolnym elemencie potoku (pipe) jest traktowany jako błąd całej komendy

### 2. Załadowanie wspólnej konfiguracji (`_config.sh`)

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_config.sh"
```

Pierwsza linia ustala ścieżkę do katalogu, w którym znajduje się skrypt. Druga linia ładuje plik konfiguracyjny `_config.sh`, który definiuje:

| Parametr | Wartość | Opis |
|---|---|---|
| `BILLING_ACCOUNT` | `017C3F-481026-534AC8` | Konto rozliczeniowe GCP przypisywane do projektu |
| `PROJECT_NAME_BASE` | `reinventor-ai-gateway-poc` | Bazowa nazwa projektu (suffix doklejany na końcu) |
| `CENTRAL_BUCKET` | `reinventor-terraform-states` | Bucket GCS przechowujący stan Terraform |
| `STATE_PREFIX_BASE` | `ai-gateway-poc` | Bazowy prefix ścieżki w buckecie |

### 3. Sprawdzenie wymagań

```bash
check_requirements
```

Funkcja zdefiniowana w `_config.sh`:

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

Skrypt weryfikuje czy na maszynie są zainstalowane wymagane narzędzia:

- **Terraform** – narzędzie Infrastructure as Code do zarządzania zasobami chmury
- **gcloud** – CLI Google Cloud

Jeśli brakuje któregoś z nich, skrypt przerywa pracę z komunikatem błędu.

### 4. Walidacja konta billingowego

```bash
: "${BILLING_ACCOUNT:?Ustaw zmienną BILLING_ACCOUNT, np. export BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX}"
```

Sprawdzenie, czy ustawiona jest zmienna `BILLING_ACCOUNT`. Konstrukcja `${VAR:?komunikat}` powoduje natychmiastowe przerwanie skryptu z podanym komunikatem, jeśli zmienna jest pusta lub niezdefiniowana. Bez konta billingowego nie można utworzyć projektu GCP.

### 5. Generowanie suffixu

```bash
if [ -n "${1:-}" ]; then
  SUFFIX="$1"
  if ! [[ "$SUFFIX" =~ ^[a-z]{4}$ ]]; then
    echo "BŁĄD: Suffix musi mieć dokładnie 4 małe litery (a-z). Podano: $SUFFIX" >&2
    exit 1
  fi
  echo ">>> Użycie podanego suffixu: ${SUFFIX}"
else
  SUFFIX=$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | LC_ALL=C tr -dc 'a-z' | head -c 4)
  echo ">>> Wylosowany suffix: ${SUFFIX}"
fi
```

Dwa tryby:

- **Z argumentem** (`$1` – pierwszy argument wiersza poleceń) – użytkownik podaje suffix (np. `abcd`). Wyrażenie regularne `^[a-z]{4}$` waliduje, że ma dokładnie 4 małe litery.
- **Bez argumentu** – skrypt losuje 4 litery:
  - `dd if=/dev/urandom bs=128 count=1` – pobiera 128 losowych bajtów
  - `tr -dc 'a-z'` – filtruje, zostawiając tylko małe litery
  - `head -c 4` – bierze pierwsze 4 znaki

Wynikowa nazwa projektu: `reinventor-ai-gateway-poc-XXXX` (np. `reinventor-ai-gateway-poc-qkhv`).

### 6. Wyświetlenie podsumowania

```bash
PROJECT_STATE_PREFIX=$(state_prefix "project")

echo "============================================"
echo " AI Gateway PoC – create-project.sh"
echo " Billing:  $BILLING_ACCOUNT"
[ -n "$ORG_ID" ] && echo " Org ID:   $ORG_ID"
[ -n "$FOLDER_ID" ] && echo " Folder:   $FOLDER_ID"
echo " Suffix:   $SUFFIX"
echo " Projekt:  ${PROJECT_NAME_BASE}-${SUFFIX}"
echo " State:    gs://${CENTRAL_BUCKET}/${PROJECT_STATE_PREFIX}/"
echo "============================================"
```

Funkcja `state_prefix "project"` (z `_config.sh`) buduje ścieżkę: `ai-gateway-poc-XXXX/project`.

Przed rozpoczęciem pracy Terraform skrypt wyświetla podsumowanie parametrów:

- konto billingowe
- suffix i pełna nazwa projektu
- lokalizacja stanu Terraform w GCS (np. `gs://reinventor-terraform-states/ai-gateway-poc-qkhv/project/`)

### 7. Terraform init – inicjalizacja

```bash
cd "$PROJECT_TF_DIR"

terraform init -reconfigure \
  -backend-config="bucket=${CENTRAL_BUCKET}" \
  -backend-config="prefix=${PROJECT_STATE_PREFIX}" \
  -input=false
```

Terraform inicjalizuje się z **remote backend** – stan infrastruktury przechowywany jest w buckecie GCS (a nie lokalnie). Parametry:

- `-reconfigure` – wymusza ponowną konfigurację backendu, co pozwala przełączać się między różnymi projektami
- `-backend-config="bucket=..."` – wskazuje bucket GCS do przechowywania stanu
- `-backend-config="prefix=..."` – unikalna ścieżka w buckecie dla tego projektu
- `-input=false` – nie pytaj interaktywnie o brakujące wartości

Dzięki temu:

- stan jest współdzielony między maszynami
- każdy projekt (suffix) ma **własny, niezależny** stan
- nie ma konfliktów między równoległymi środowiskami

### 8. Terraform apply – tworzenie projektu

```bash
TF_VARS=(
  -var="billing_account=${BILLING_ACCOUNT}"
  -var="suffix=${SUFFIX}"
)
[ -n "$ORG_ID" ] && TF_VARS+=(-var="org_id=${ORG_ID}")
[ -n "$FOLDER_ID" ] && TF_VARS+=(-var="folder_id=${FOLDER_ID}")

terraform apply "${TF_VARS[@]}"
```

Skrypt buduje tablicę zmiennych Terraform i uruchamia `terraform apply`. Terraform tworzy projekt GCP z następującymi parametrami:

| Parametr | Źródło |
|---|---|
| Nazwa i ID projektu | `reinventor-ai-gateway-poc-{suffix}` |
| Konto billingowe | zmienna `BILLING_ACCOUNT` |
| Organizacja (opcjonalnie) | zmienna `ORG_ID` |
| Folder (opcjonalnie) | zmienna `FOLDER_ID` |

Terraform wyświetla plan zmian i czeka na potwierdzenie użytkownika (`yes`).

### 9. Pobranie ID projektu z Terraform

```bash
NEW_PROJECT_ID=$(terraform output -raw project_id 2>/dev/null) || true

if [ -z "$NEW_PROJECT_ID" ]; then
  echo "BŁĄD: Nie udało się pobrać outputów Terraform (project_id)." >&2
  exit 1
fi
```

Po utworzeniu projektu skrypt odczytuje wygenerowane `project_id` z outputów Terraform. `|| true` zapobiega przerwaniu skryptu w przypadku błędu komendy (sprawdzenie następuje w kolejnym `if`). Jeśli nie uda się go pobrać, skrypt przerywa pracę.

### 10. Zapis `.project-env`

```bash
cat > "${ROOT_DIR}/.project-env" <<EOF
# Wygenerowane automatycznie przez create-project.sh
# $(date -u +"%Y-%m-%d %H:%M:%S UTC")
PROJECT_ID=${NEW_PROJECT_ID}
SUFFIX=${SUFFIX}
EOF
```

Skrypt zapisuje plik `.project-env` w katalogu głównym repozytorium. Konstrukcja `<<EOF ... EOF` to tzw. heredoc – pozwala zapisać wieloliniowy tekst do pliku.

Przykładowa zawartość:

```
# Wygenerowane automatycznie przez create-project.sh
# 2026-11-25 10:26:34 UTC
PROJECT_ID=reinventor-ai-gateway-poc-qkhv
SUFFIX=qkhv
```

Ten plik jest automatycznie odczytywany przez pozostałe skrypty (`bootstrap.sh`, `up.sh`, `down.sh`, `destroy-project.sh`), więc nie trzeba za każdym razem podawać suffixu.

### 11. Weryfikacja projektu w GCP

```bash
if gcloud projects describe "$NEW_PROJECT_ID" >/dev/null 2>&1; then
  echo "  Projekt zweryfikowany w GCP."
else
  echo "UWAGA: Projekt $NEW_PROJECT_ID nie jest jeszcze widoczny w GCP."
fi
```

Skrypt sprawdza przez `gcloud` czy nowo utworzony projekt jest już widoczny w GCP. Czasem propagacja trwa kilka sekund. Jeśli projekt nie jest jeszcze widoczny, wyświetla ostrzeżenie (ale nie przerywa pracy).

### 12. Przełączenie kontekstu gcloud

```bash
gcloud config set project "$NEW_PROJECT_ID"
```

Ustawia nowy projekt jako aktywny w sesji gcloud. Dzięki temu kolejne komendy `gcloud` będą domyślnie operować na tym projekcie.

### 13. Podsumowanie końcowe

```bash
echo " Project ID:  $NEW_PROJECT_ID"
echo " Suffix:      $SUFFIX"
echo " State:       gs://${CENTRAL_BUCKET}/${PROJECT_STATE_PREFIX}/"
echo ""
echo " Plik .project-env zapisany – pozostałe skrypty"
echo " automatycznie odczytają PROJECT_ID i SUFFIX."
echo ""
echo " Następne kroki:"
echo "   ./scripts/bootstrap.sh"
echo "   ./scripts/up.sh"
```

Skrypt wyświetla:

- Project ID i suffix
- Lokalizację stanu Terraform
- Następne kroki do wykonania (`bootstrap.sh` → `up.sh`)

## Schemat przepływu

```
Użytkownik uruchamia skrypt
        │
        ▼
Załadowanie konfiguracji (_config.sh)
        │
        ▼
Sprawdzenie: terraform, gcloud zainstalowane?
        │ NIE → błąd, koniec
        ▼ TAK
Sprawdzenie: BILLING_ACCOUNT ustawione?
        │ NIE → błąd, koniec
        ▼ TAK
Generowanie/walidacja 4-literowego suffixu
        │
        ▼
Wyświetlenie podsumowania parametrów
        │
        ▼
Terraform init (konfiguracja remote backend w GCS)
        │ BŁĄD → koniec
        ▼ OK
Terraform apply (tworzenie projektu GCP)
        │ BŁĄD → koniec
        ▼ OK
Pobranie project_id z outputów Terraform
        │
        ▼
Zapis .project-env (PROJECT_ID + SUFFIX)
        │
        ▼
Weryfikacja projektu w GCP (gcloud)
        │
        ▼
Przełączenie kontekstu gcloud na nowy projekt
        │
        ▼
Gotowe – następny krok: bootstrap.sh
```

## Powiązanie z innymi skryptami

| Skrypt | Rola | Zależność od create-project.sh |
|---|---|---|
| `bootstrap.sh` | Aktywacja API, konfiguracja SA i uprawnień | Czyta `.project-env` lub przyjmuje suffix jako argument |
| `up.sh` | Tworzenie infrastruktury (GKE, deploy LiteLLM) | Czyta `.project-env` lub przyjmuje suffix jako argument |
| `down.sh` | Usunięcie infrastruktury (zachowuje projekt) | Czyta `.project-env` lub przyjmuje suffix jako argument |
| `destroy-project.sh` | Usunięcie projektu GCP i czyszczenie stanów w GCS | Czyta `.project-env` lub przyjmuje suffix jako argument |
