# 05 – Teardown

## Kiedy

Po zakończeniu sesji testowej. **Zawsze** uruchom teardown, aby uniknąć niepotrzebnych kosztów.

## Dwa poziomy teardown

| Poziom | Skrypt | Co usuwa | Kiedy używać |
|---|---|---|---|
| Zasoby | `down.sh` | Helm, K8s, GCR image, Terraform infra | Po każdej sesji testowej |
| Projekt | `destroy-project.sh` | Cały projekt GCP | Gdy nie planujesz wrócić do tego projektu |

## Poziom 1 – Usunięcie zasobów (down.sh)

### Uruchomienie

```bash
./scripts/down.sh
```

Skrypt poprosi o potwierdzenie (`y`).

### Co robi (4 kroki)

| Krok | Opis |
|---|---|
| 1/4 | Helm uninstall – LiteLLM (z Postgres i Redis) |
| 2/4 | Usunięcie K8s resources – mock-backend, secrets, configmap |
| 3/4 | Usunięcie obrazu Docker z GCR |
| 4/4 | Terraform destroy – GKE cluster, VPC, IAM |

### Co pozostaje

- **Projekt GCP** – nadal istnieje
- **Terraform state** – w centralnym buckecie `reinventor-terraform-states`
- **Plik `.project-env`** – z PROJECT_ID i SUFFIX

### Ponowne uruchomienie środowiska

Aby ponownie uruchomić środowisko w tym samym projekcie:

```bash
./scripts/bootstrap.sh   # Pomiń jeśli SA nadal istnieje
./scripts/up.sh
```

## Poziom 2 – Usunięcie projektu (destroy-project.sh)

### Kiedy

- Kończysz pracę ze środowiskiem na dłużej
- Chcesz zacząć od zera z nowym projektem
- Chcesz zwolnić nazwę projektu

### Przed usunięciem projektu

Najpierw usuń zasoby, potem projekt:

```bash
# 1. Zasoby
./scripts/down.sh

# 2. Projekt
./scripts/destroy-project.sh
```

### Co się dzieje

- `terraform destroy` niszczy zasoby w `terraform/project/`
- `deletion_policy = "DELETE"` powoduje natychmiastowe usunięcie projektu GCP
- Plik `.project-env` zostaje usunięty
- Nowy projekt z `create-project.sh` otrzyma inny suffix

### Ponowne rozpoczęcie od zera

```bash
./scripts/create-project.sh    # Nowy projekt z nowym suffixem
./scripts/bootstrap.sh
./scripts/up.sh
```

## Czyszczenie lokalne

Plik `.project-env` w katalogu głównym repozytorium zawiera PROJECT_ID i SUFFIX. Jest automatycznie usuwany przez `destroy-project.sh`.

Terraform state przechowywany jest zdalnie w buckecie `reinventor-terraform-states` – nie ma lokalnych plików state do czyszczenia.

Foldery `.terraform/` w podkatalogach `terraform/` zawierają cache providerów. Można je bezpiecznie usunąć – zostaną odtworzone przy następnym `terraform init`.

## Weryfikacja po teardown

```bash
# Sprawdź czy nie zostały zasoby GCP
gcloud projects describe $PROJECT_ID 2>/dev/null || echo "Projekt nie istnieje"
gcloud compute instances list --project=$PROJECT_ID 2>/dev/null
gcloud container clusters list --project=$PROJECT_ID 2>/dev/null
```
