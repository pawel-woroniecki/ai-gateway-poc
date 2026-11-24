# 04 – Testowanie

## Kiedy

Po pomyślnym deployu środowiska (krok 03).

## Wymagania wstępne

- Środowisko uruchomione ([03-deploy-srodowiska.md](03-deploy-srodowiska.md))
- Port-forward do LiteLLM aktywny

## Uruchomienie port-forward

```bash
kubectl port-forward svc/litellm 4000:4000
```

Pozostaw terminal otwarty. Testy wykonuj w drugim terminalu.

## Testy podstawowe

### Health check

```bash
curl http://localhost:4000/health/liveliness
```

Oczekiwana odpowiedź: `"connected"`

### Lista modeli

```bash
curl http://localhost:4000/model/info \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq .
```

### Chat completion – mock backend

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{
    "model": "mock-local",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### Chat completion – Gemini Flash (Vertex AI)

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{
    "model": "gemini-flash",
    "messages": [{"role": "user", "content": "Co to jest AI Gateway?"}]
  }'
```

### Chat completion – Claude Sonnet (wymaga ANTHROPIC_API_KEY)

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{
    "model": "claude-sonnet",
    "messages": [{"role": "user", "content": "Czym jest shadow AI?"}]
  }'
```

## Weryfikacja metadanych stref

Każdy model ma przypisaną strefę danych w `model_info.metadata.zone`. Sprawdź, czy metadane są poprawnie zwracane:

```bash
curl http://localhost:4000/model/info \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  | jq '.data[] | {model_name, zone: .model_info.metadata.zone}'
```

Oczekiwany wynik:

```json
{"model_name": "gemini-flash", "zone": "C-EU"}
{"model_name": "claude-sonnet", "zone": "C-GL"}
{"model_name": "mock-local", "zone": "local"}
```

## Sprawdzanie logów

```bash
# Logi LiteLLM
kubectl logs -l app.kubernetes.io/name=litellm -f

# Logi mock backend
kubectl logs -l app=mock-backend -f

# Status podów
kubectl get pods
```

## Rozwiązywanie problemów

| Problem | Przyczyna | Rozwiązanie |
|---|---|---|
| `connection refused` na :4000 | Port-forward nie działa | Sprawdź `kubectl port-forward`, restart |
| `AuthenticationError` | Brak lub błędny master key | Sprawdź `echo $LITELLM_MASTER_KEY` |
| `model not found` | Model nie zdefiniowany w config | Sprawdź `config/litellm/config.yaml` |
| Pod w `CrashLoopBackOff` | Błąd konfiguracji | `kubectl logs <pod-name>` |
| `Vertex AI 403` | Brak uprawnień lub API wyłączone | Sprawdź `gcloud services list` |
| Timeout na Anthropic | Brak klucza API | Ustaw `ANTHROPIC_API_KEY` i reapply secrets |

## Następny krok

→ [05-teardown.md](05-teardown.md)
