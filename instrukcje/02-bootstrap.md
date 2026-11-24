# 02 – Bootstrap

## Kiedy

Po utworzeniu projektu GCP (krok 01). Uruchamiany raz – tworzy zasoby wymagane przed deploym infrastruktury.

## Wymagania wstępne

- Projekt GCP utworzony ([01-tworzenie-projektu.md](01-tworzenie-projektu.md))
- `gcloud` zalogowane i wskazujące na właściwy projekt

## Zmienne środowiskowe

| Zmienna | Wymagana | Opis |
|---|---|---|
| `PROJECT_ID` | Auto* | ID projektu GCP |
| `SUFFIX` | Auto* | 4-literowy suffix projektu |
| `REGION` | Nie | Region GCP (domyślnie: `europe-central2`) |

\* `PROJECT_ID` i `SUFFIX` są automatycznie odczytywane z `.project-env`, jeśli projekt został utworzony przez `create-project.sh`.

## Kroki

### 1. Uruchom bootstrap

```bash
./scripts/bootstrap.sh
```

Skrypt:
- Automatycznie odczyta `PROJECT_ID` i `SUFFIX` z `.project-env`
- Ustawi `gcloud config set project`
- Uruchomi `terraform init` z backendem GCS (prefix `ai-gateway-poc-{suffix}/bootstrap`)
- Uruchomi `terraform apply` – poprosi o potwierdzenie (`yes`)

### 2. Zweryfikuj outputy

Po zakończeniu skrypt wyświetli:

```
Terraform SA: ai-gateway-terraform@reinventor-ai-gateway-poc-abcd.iam.gserviceaccount.com
```

## Co tworzy ten krok

| Zasób | Opis |
|---|---|
| Service Account | `ai-gateway-terraform` – SA z rolami do zarządzania infra |
| API | compute, container, iam, aiplatform, cloudresourcemanager, serviceusage |

### Role przypisane do SA

- `roles/container.admin` – zarządzanie GKE
- `roles/compute.networkAdmin` – sieć i firewall
- `roles/iam.serviceAccountAdmin` – zarządzanie SA
- `roles/iam.serviceAccountUser` – używanie SA
- `roles/storage.admin` – GCS
- `roles/aiplatform.user` – Vertex AI
- `roles/serviceusage.serviceUsageAdmin` – włączanie API

## Terraform state

State w centralnym buckecie GCS `reinventor-terraform-states`, prefix `ai-gateway-poc-{suffix}/bootstrap`.

## Następny krok

→ [03-deploy-srodowiska.md](03-deploy-srodowiska.md)
