# 03 – Deploy środowiska

## Kiedy

Po zakończeniu bootstrapu (krok 02). Stawia pełne środowisko: infrastrukturę GKE, mock backend, LiteLLM z Helm.

## Wymagania wstępne

- Bootstrap zakończony ([02-bootstrap.md](02-bootstrap.md))
- Docker uruchomiony (do budowy obrazu mock backend)
- `kubectl` i `helm` zainstalowane

## Zmienne środowiskowe

| Zmienna | Wymagana | Opis |
|---|---|---|
| `PROJECT_ID` | Auto* | ID projektu GCP |
| `SUFFIX` | Auto* | 4-literowy suffix projektu |
| `REGION` | Nie | Domyślnie: `europe-central2` |
| `ZONE` | Nie | Domyślnie: `europe-central2-a` |
| `CLUSTER_NAME` | Nie | Domyślnie: `ai-gateway-cluster` |
| `ANTHROPIC_API_KEY` | Nie | Klucz API Anthropic (do testów z Claude) |
| `LANGFUSE_PUBLIC_KEY` | Nie | Klucz publiczny Langfuse |
| `LANGFUSE_SECRET_KEY` | Nie | Klucz prywatny Langfuse |

\* `PROJECT_ID` i `SUFFIX` są automatycznie odczytywane z `.project-env`, jeśli projekt został utworzony przez `create-project.sh`.

## Kroki

### 1. Ustaw klucze API (opcjonalnie)

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

Bez klucza model `claude-sonnet` nie będzie dostępny, ale `gemini-flash` (Vertex AI) i `mock-local` będą działać.

### 2. Uruchom deploy

```bash
./scripts/up.sh
```

### 3. Co robi skrypt (5 kroków)

| Krok | Opis |
|---|---|
| 1/5 | Terraform apply – VPC, subnet, firewall, GKE, IAM, Workload Identity |
| 2/5 | Konfiguracja kubectl – pobranie credentials klastra |
| 3/5 | Mock backend – build Docker image, push do GCR, deploy do K8s |
| 4/5 | Secrets – master key LiteLLM, klucze API, ConfigMap z config.yaml |
| 5/5 | Helm install – LiteLLM Proxy z Postgres i Redis |

### 4. Weryfikacja

```bash
# Port-forward do LiteLLM
kubectl port-forward svc/litellm 4000:4000

# Health check
curl http://localhost:4000/health/liveliness

# Lista modeli
curl http://localhost:4000/model/info \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

## Co tworzy ten krok

### Infrastruktura (Terraform)

| Zasób | Opis |
|---|---|
| VPC | `ai-gateway-vpc` z jednym subnetem |
| Firewall | Reguły dla ruchu wewnętrznego |
| GKE Cluster | Zonal, 1 node `e2-standard-2`, darmowy control plane |
| Service Accounts | `ai-gateway-litellm` z Workload Identity |

### Kubernetes

| Zasób | Opis |
|---|---|
| mock-backend | Deployment + Service (OpenAI-compatible mock) |
| litellm-secrets | Secret z master key |
| litellm-env | Secret z kluczami API |
| litellm-config | ConfigMap z config.yaml |
| litellm (Helm) | LiteLLM Proxy + Postgres + Redis |

## Konfiguracja modeli

Modele zdefiniowane w `config/litellm/config.yaml`:

| Model | Backend | Strefa danych |
|---|---|---|
| `gemini-flash` | Vertex AI (`europe-west1`) | C-EU |
| `claude-sonnet` | Anthropic API | C-GL |
| `mock-local` | Mock backend w klastrze | local |

## Szacowane koszty

- GKE control plane (zonal): **darmowy**
- 1x e2-standard-2 node: ~$0.07/h
- Sesja testowa (2–4h): **~$0.15–0.30**
- Vertex AI / Anthropic API: wg zużycia (testy z mock backend: $0)

## Następny krok

→ [04-testowanie.md](04-testowanie.md)
