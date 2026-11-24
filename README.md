# AI Gateway PoC

Osobiste środowisko testowe architekta do weryfikacji architektury AI Gateway na Google Cloud Platform.

## Cel

- Weryfikacja decyzji architektonicznych z [HLD AI Gateway v0.4](docs/HLD_AI_Gateway_v0.4.md)
- Nabranie doświadczenia z komponentami: LiteLLM, OPA, Presidio, PCA
- Przejście scenariuszy testowych z dokumentacji PoC
- Budowa reużywalnej automatyzacji IaC (Terraform + Helm) dla przyszłych klientów

## Architektura

```
┌──────────────────────────────────────────────────────┐
│  GKE Cluster (e2-standard-2, 1 node)                 │
│                                                      │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  LiteLLM   │  │  Mock        │  │  Postgres    │  │
│  │  Proxy     │  │  Backend     │  │  + Redis     │  │
│  │  :4000     │  │  :8080       │  │              │  │
│  └─────┬──────┘  └──────────────┘  └──────────────┘  │
│        │                                             │
└────────┼─────────────────────────────────────────────┘
         │
    ┌────┴────────────────────┐
    │    Backendy LLM         │
    ├─────────────────────────┤
    │ Vertex AI Gemini Flash  │  strefa C-EU
    │ Anthropic Claude        │  strefa C-GL
    │ Mock backend            │  strefa local
    └─────────────────────────┘
```

**Strefy danych** symulują fizyczny podział z architektury produkcyjnej. Backendy API reprezentują poszczególne strefy (local, C-EU, C-GL), a reguły routingu w PCA/OPA decydują, które strefy są dozwolone dla danego żądania.

## Struktura repozytorium

```
ai-gateway-poc/
├── config/
│   ├── litellm/config.yaml       # Konfiguracja modeli i routingu LiteLLM
│   ├── i18n/error_messages_pl.json
│   └── seed/init.sql             # Dane inicjalizacyjne
├── helm/
│   └── values/litellm-dev.yaml   # Wartości Helm dla środowiska dev
├── instrukcje/                   # Instrukcje obsługi (krok po kroku)
│   ├── 01-tworzenie-projektu.md
│   ├── 02-bootstrap.md
│   ├── 03-deploy-srodowiska.md
│   ├── 04-testowanie.md
│   └── 05-teardown.md
├── mock/
│   ├── Dockerfile                # Mock backend OpenAI-compatible
│   ├── server.py
│   └── k8s.yaml
├── scripts/
│   ├── create-project.sh         # Tworzenie projektu GCP (z losowym suffixem)
│   ├── destroy-project.sh        # Usuwanie projektu GCP
│   ├── _config.sh                # Wspólna konfiguracja (bucket, prefixy)
│   ├── bootstrap.sh              # Inicjalizacja: SA, API
│   ├── up.sh                     # Pełny deploy środowiska
│   └── down.sh                   # Teardown zasobów (bez projektu)
├── terraform/
│   ├── project/                  # Moduł tworzenia projektu GCP
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── bootstrap/
│   │   └── main.tf               # SA, API
│   ├── environments/
│   │   └── dev/
│   │       ├── main.tf           # Root module (networking + GKE + IAM)
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── terraform.tfvars.example
│   └── modules/
│       ├── networking/main.tf    # VPC, subnet, firewall
│       ├── gke/main.tf           # GKE zonal cluster
│       └── iam/main.tf           # Service accounts, Workload Identity
└── .gitignore
```

## Szybki start

### Wymagania

- [Terraform](https://www.terraform.io/) >= 1.5
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) – zalogowany (`gcloud auth login`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.x
- [Docker](https://docs.docker.com/get-docker/)
- Konto GCP z aktywnym billingiem

### Workflow

```
1. create-project.sh   →  Tworzenie projektu GCP (unikalna nazwa z suffixem)
2. bootstrap.sh        →  Service account, API
3. up.sh               →  Terraform + kubectl + Docker + Helm
                           ↕ (testy)
4. down.sh             ←  Teardown zasobów infrastrukturalnych
5. destroy-project.sh  ←  Usunięcie projektu GCP (opcjonalnie)
```

Szczegółowe instrukcje: patrz folder [`instrukcje/`](instrukcje/).

### Minimalne kroki

```bash
# 1. Ustaw billing account
export BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"

# 2. Utwórz projekt GCP
./scripts/create-project.sh

# 3. Bootstrap (PROJECT_ID wykryty automatycznie)
./scripts/bootstrap.sh

# 4. Deploy
export ANTHROPIC_API_KEY="sk-ant-..."    # opcjonalnie
./scripts/up.sh

# 5. Test
kubectl port-forward svc/litellm 4000:4000
curl http://localhost:4000/health/liveliness

# 6. Teardown
./scripts/down.sh

# 7. Usunięcie projektu (opcjonalnie)
./scripts/destroy-project.sh
```

## Zarządzanie projektem GCP

Nazwa projektu ma format `reinventor-ai-gateway-poc-XXXX`, gdzie `XXXX` to losowy 4-literowy suffix. Dzięki temu:

- Każdy nowy projekt ma unikalną nazwę
- Można usunąć projekt i natychmiast utworzyć nowy – bez czekania na 30-dniowy okres retencji GCP
- `deletion_policy = "DELETE"` w Terraform zapewnia natychmiastowe usunięcie

## Terraform state

Wszystkie state files przechowywane w centralnym buckecie GCS `reinventor-terraform-states` (w osobnym projekcie GCP). Struktura:

```
reinventor-terraform-states/
  ai-gateway-poc/
    project/default.tfstate         ← moduł project (prefix stały)
  ai-gateway-poc-{suffix}/
    bootstrap/default.tfstate       ← bootstrap (prefix z suffixem)
    dev/default.tfstate             ← środowisko dev (prefix z suffixem)
```

Prefix modułu `project` jest stały (`ai-gateway-poc/project`), ponieważ suffix jest generowany dopiero w tym module. Pozostałe moduły używają prefiksu z suffixem (`ai-gateway-poc-{suffix}/...`).

Skrypt `create-project.sh` zapisuje PROJECT_ID i SUFFIX do pliku `.project-env`, który pozostałe skrypty automatycznie odczytują.

## Budżet i koszty

- Budżet: **$300** (GCP free credits)
- Zasoby powoływane i niszczone per sesja testowa
- Szacowany koszt sesji: **~$0.50** (GKE zonal – darmowy control plane + 1 node e2-standard-2)
- Po zakończeniu testów **zawsze** uruchom `down.sh`

## Fazy rozwoju

| Faza | Zakres | Status |
|---|---|---|
| 0 | Infrastruktura IaC (Terraform, GKE, networking, IAM) | ✅ Gotowe |
| 1 | LiteLLM basic (Helm, config, mock backend, skrypty) | ✅ Gotowe |
| 2 | OPA + PCA (polityki routingu, klasyfikacja treści) | Planowane |
| 3 | Guardrails (PII detection, content filtering) | Planowane |
| 4 | Observability (Langfuse, metryki, alerty) | Planowane |

## Dokumentacja projektowa

Pełna dokumentacja architektoniczna znajduje się w projekcie Claude AI (AI Gateway):

- **HLD AI Gateway v0.4** – architektura produkcyjna
- **HLD środowiska PoC** – architektura tego środowiska testowego
- **Plan pracy** – fazy, zadania, ryzyka
- **Analiza opcji** – porównanie LiteLLM, Agent Router, agentgateway
- **PCA** – Policy & Classification Adapter
- **Porównanie IaC** – warianty pod kątem infrastruktury jako kodu

## Licencja

Repozytorium prywatne. Kod IaC przeznaczony do reużycia w projektach klientowskich.
