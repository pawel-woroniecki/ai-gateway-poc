# 06 – LiteLLM Admin UI

## Kiedy

Po pomyślnym deployu środowiska (krok 03) – do zarządzania modelami,
kluczami API, użytkownikami i monitorowania ruchu przez przeglądarkę.

## Wymagania wstępne

- Środowisko uruchomione ([03-deploy-srodowiska.md](03-deploy-srodowiska.md))
- Port-forward do LiteLLM aktywny

## Uruchomienie port-forward

Skrypt `up.sh` uruchamia port-forward automatycznie. Jeśli trzeba
uruchomić ręcznie:

```bash
# Użyj deploy/ zamiast svc/ – svc/ może trafić na pod migracji
kubectl rollout status deploy/litellm --timeout=120s
kubectl port-forward deploy/litellm 4000:4000 &
```

## Dostęp przez Cloud Shell Web Preview

1. W Cloud Shell kliknij ikonę **Web Preview** (prawy górny róg)
2. Wybierz **Change port** → wpisz `4000` (lub port podany przez `up.sh`)
   → **Change and Preview**
3. Przeglądarka otworzy URL w formacie:
   `https://4000-cs-XXXXX.cs-europe-west1-XXXX.cloudshell.dev/ui`

> Jeśli otworzy się strona główna LiteLLM (nie UI), dodaj `/ui` na końcu URL.

## Logowanie

Credentials ustawione w `helm/values/litellm-dev.yaml`:

- **Username**: `admin`
- **Password**: `sk-aigw-master-poc-dev`

Te wartości pochodzą z `envVars.UI_USERNAME` i `envVars.UI_PASSWORD`.

## Endpointy logowania (wersja 1.112+)

LiteLLM ma kilka endpointów logowania – ważne jest użycie właściwego:

| Endpoint | Content-Type | Opis |
|----------|-------------|------|
| `/v2/login` | `application/json` | **Główny** – używany przez UI, zwraca JSON z tokenem JWT |
| `/login` | `application/x-www-form-urlencoded` | Helper dla SSO, oczekuje form data (nie JSON!) |
| `/auth/login` | `application/json` | Tylko gdy `is_control_plane: true` (domyślnie wyłączony) |

> **Uwaga**: wysłanie JSON do `/login` zwróci 401 – to NIE oznacza
> złych kredencjali, tylko zły Content-Type.

## Weryfikacja logowania przez curl

```bash
# Poprawny test – /v2/login z JSON
curl -s -X POST http://localhost:4000/v2/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"sk-aigw-master-poc-dev"}' \
  | python3 -m json.tool
```

Poprawna odpowiedź:

```json
{
    "redirect_url": "http://localhost:4000/ui?login=success",
    "token": "eyJhbG..."
}
```

Alternatywnie, test przez form data:

```bash
# /login z form data
curl -s -X POST http://localhost:4000/login \
  -d "username=admin&password=sk-aigw-master-poc-dev" \
  -v 2>&1 | grep "HTTP/1.1\|location:"
```

Poprawna odpowiedź: `HTTP/1.1 303 See Other` z `location: .../ui?login=success`.

## Scenariusz B: baza ma już użytkowników

Po kilku `helm upgrade` LiteLLM może automatycznie stworzyć użytkownika
w bazie PostgreSQL. Od tego momentu env-based login (`UI_USERNAME`/`UI_PASSWORD`)
może być ignorowany – akceptowani są tylko użytkownicy z bazy.

Objawy: po wpisaniu kredencjali ekran logowania wraca do początku
(bez komunikatu o błędzie lub z komunikatem "Invalid credentials").

### Rozwiązanie: stworzenie użytkownika przez API

1. Upewnij się, że port-forward działa
2. Stwórz użytkownika:

```bash
curl -s -X POST http://localhost:4000/user/new \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer sk-aigw-master-poc-dev' \
  -d '{
    "user_email": "admin@poc.local",
    "user_role": "proxy_admin",
    "auto_create_key": true
  }' | python3 -m json.tool
```

3. Ustaw hasło (min. 12 znaków, wielka litera, znak specjalny):

```bash
curl -s -X POST http://localhost:4000/user/update \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer sk-aigw-master-poc-dev' \
  -d '{
    "user_id": "<USER_ID_Z_KROKU_2>",
    "password": "Admin123poc!"
  }' | python3 -m json.tool
```

4. Zaloguj się:
   - **Username**: `admin@poc.local`
   - **Password**: `Admin123poc!`

### Alternatywa: reset bazy PostgreSQL

Dla PoC można po prostu usunąć pod PostgreSQL (baza używa emptyDir,
dane nie przetrwają restartu):

```bash
kubectl delete pod litellm-postgresql-0
kubectl rollout restart deployment litellm
```

Po restarcie wracamy do logowania z env vars.

## Sprawdzenie env vars w podzie

```bash
kubectl exec deploy/litellm -- env | grep -E "UI_|MASTER"
```

Oczekiwany wynik:

```
UI_PASSWORD=sk-aigw-master-poc-dev
PROXY_MASTER_KEY=sk-aigw-master-poc-dev
UI_USERNAME=admin
```

## Rozwiązywanie problemów

| Problem | Przyczyna | Rozwiązanie |
|---------|-----------|-------------|
| Port 4000 zajęty | Stary port-forward w tle | `pkill -f "port-forward"` |
| curl 401 na `/login` z JSON | Zły Content-Type | Użyj `/v2/login` z JSON lub `/login` z form data |
| "Loading..." → powrót do loginu | Env-based auth wyłączony | Scenariusz B powyżej |
| "Internal server error" | Brak tabel w bazie | `kubectl rollout restart deployment litellm` |
| "User has no password set" | User w bazie bez hasła | Ustaw hasło przez `/user/update` |
| Port-forward trafia na pod migracji | Użyto `svc/litellm` | Użyj `deploy/litellm` zamiast `svc/litellm` |
