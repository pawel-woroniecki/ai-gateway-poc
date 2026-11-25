# 06 – LiteLLM Admin UI

## Kiedy

Po pomyślnym deployu środowiska (krok 03) – do zarządzania modelami,
kluczami API, użytkownikami i monitorowania ruchu przez przeglądarkę.

## Wymagania wstępne

- Środowisko uruchomione ([03-deploy-srodowiska.md](03-deploy-srodowiska.md))
- Port-forward do LiteLLM aktywny

## Uruchomienie port-forward

```bash
kubectl port-forward svc/litellm 4000:4000
```

## Dostęp przez Cloud Shell Web Preview

1. W Cloud Shell kliknij ikonę **Web Preview** (prawy górny róg)
2. Wybierz **Change port** → wpisz `4000` → **Change and Preview**
3. Przeglądarka otworzy URL w formacie:
   `https://4000-cs-XXXXX.cs-europe-west1-XXXX.cloudshell.dev/ui`

> Jeśli otworzy się strona główna LiteLLM (nie UI), dodaj `/ui` na końcu URL.

## Logowanie – scenariusz A: świeży deploy

Na świeżej bazie PostgreSQL (pierwszy deploy lub po resecie bazy)
LiteLLM akceptuje kredencjale z env vars:

- **Username**: `admin`
- **Password**: `sk-aigw-master-poc-dev`

Te wartości pochodzą z `envVars.UI_USERNAME` i `envVars.UI_PASSWORD`
w `helm/values/litellm-dev.yaml`.

## Logowanie – scenariusz B: baza ma już użytkowników

Po kilku `helm upgrade` LiteLLM może automatycznie stworzyć użytkownika
w bazie PostgreSQL. Od tego momentu env-based login (`UI_USERNAME`/`UI_PASSWORD`)
jest ignorowany – akceptowani są tylko użytkownicy z bazy.

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

Po restarcie wracamy do scenariusza A (świeży deploy).

## Weryfikacja logowania przez curl

Gdy UI nie działa, sprawdź backend bezpośrednio:

```bash
# Test z env-based credentials
curl -s -X POST http://localhost:4000/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"sk-aigw-master-poc-dev"}'

# Test z database credentials
curl -s -X POST http://localhost:4000/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin@poc.local","password":"Admin123poc!"}'
```

Poprawna odpowiedź zawiera token JWT. Odpowiedź `401` oznacza
nieprawidłowe kredencjale.

## Rozwiązywanie problemów

| Problem | Przyczyna | Rozwiązanie |
|---------|-----------|-------------|
| Port 4000 zajęty | Stary port-forward w tle | `pkill -f "port-forward"` |
| "Loading..." → powrót do loginu | Env-based auth wyłączony | Scenariusz B powyżej |
| "Internal server error" | Brak tabel w bazie | `kubectl rollout restart deployment litellm` |
| "User has no password set" | User w bazie bez hasła | Ustaw hasło przez `/user/update` |
| curl 404 na `/user/login` | Stary endpoint | Użyj `/login` (bez `/user/`) |
