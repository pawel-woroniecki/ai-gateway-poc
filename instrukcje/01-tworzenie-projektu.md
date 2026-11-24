# 01 – Tworzenie projektu GCP

## Kiedy

Na początku pracy ze środowiskiem PoC, lub po usunięciu poprzedniego projektu (`destroy-project.sh`).

## Wymagania wstępne

- `gcloud` CLI zainstalowane i zalogowane (`gcloud auth login`)
- Terraform >= 1.5
- Aktywne konto billingowe GCP
- (Opcjonalnie) ID organizacji lub folderu GCP

## Zmienne środowiskowe

| Zmienna | Wymagana | Opis |
|---|---|---|
| `BILLING_ACCOUNT` | Tak | ID konta billingowego, format `XXXXXX-XXXXXX-XXXXXX` |
| `ORG_ID` | Nie | ID organizacji GCP (jeśli projekt ma być w organizacji) |
| `FOLDER_ID` | Nie | ID folderu GCP (jeśli projekt ma być w folderze) |

## Kroki

### 1. Sprawdź ID konta billingowego

```bash
gcloud billing accounts list
```

### 2. Ustaw zmienne

```bash
export BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"

# Opcjonalnie:
# export ORG_ID="123456789"
# export FOLDER_ID="987654321"
```

### 3. Uruchom skrypt

```bash
./scripts/create-project.sh
```

Skrypt wykona:
- `terraform init` z backendem GCS (`reinventor-terraform-states`)
- `terraform apply` – wyświetli plan i poprosi o potwierdzenie (`yes`)
- Zapisze `PROJECT_ID` i `SUFFIX` do `.project-env`

### 4. Zanotuj Project ID

Po zakończeniu skrypt wyświetli:

```
 Project ID:  reinventor-ai-gateway-poc-abcd
 Suffix:      abcd
```

Skrypt automatycznie zapisuje te wartości do pliku `.project-env` w katalogu głównym repozytorium. Pozostałe skrypty (`bootstrap.sh`, `up.sh`, `down.sh`) automatycznie je odczytują.

Jeśli chcesz je ustawić jawnie:

```bash
export PROJECT_ID=reinventor-ai-gateway-poc-abcd
export SUFFIX=abcd
```

## Co tworzy ten krok

| Zasób | Opis |
|---|---|
| Projekt GCP | `reinventor-ai-gateway-poc-XXXX` (XXXX = losowy suffix) |
| API: Cloud Resource Manager | Zarządzanie zasobami |
| API: Service Usage | Włączanie kolejnych API |
| API: Cloud Billing | Powiązanie z kontem billingowym |

## Jak to działa

- `random_string` generuje 4-literowy suffix (tylko małe litery)
- Suffix jest powiązany z bazową nazwą projektu przez `keepers` – zmiana bazy wymusza nowy suffix
- `deletion_policy = "DELETE"` pozwala na natychmiastowe usunięcie projektu
- Terraform state w centralnym buckecie GCS `reinventor-terraform-states`, prefix `ai-gateway-poc/project`
- Plik `.project-env` przechowuje PROJECT_ID i SUFFIX dla pozostałych skryptów

## Następny krok

→ [02-bootstrap.md](02-bootstrap.md)
