# 06 – LiteLLM Admin UI

## Kiedy

Po pomyślnym deployu środowiska (krok 03) – do zarządzania modelami,
kluczami API, użytkownikami i monitorowania ruchu przez przeglądarkę.

## Wymagania wstępne

- Środowisko uruchomione ([03-deploy-srodowiska.md](03-deploy-srodowiska.md))

## Dostęp do UI

LiteLLM jest wystawiony jako **Service type LoadBalancer** z zewnętrznym
adresem IP. Skrypt `up.sh` wyświetla adres po deployu.

Ręczne sprawdzenie adresu:

```bash
kubectl get svc litellm -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Otwórz w przeglądarce:

```
http://EXTERNAL-IP:4000/ui
```

> **Dlaczego LoadBalancer zamiast Cloud Shell Web Preview?**
> Cloud Shell Web Preview działa jako reverse proxy, który stripuje
> nagłówki `Set-Cookie` z odpowiedzi HTTP. To uniemożliwia logowanie
> do UI, ponieważ przeglądarka nie otrzymuje tokena sesji.
> LoadBalancer daje bezpośrednie połączenie z LiteLLM bez proxy.

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

Z Cloud Shell (port-forward lub external IP):

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

## Migracje bazy danych

LiteLLM wymaga tabel w PostgreSQL (Prisma ORM). Helm chart uruchamia
migrations job jako pre-install hook, ale może on failować gdy PostgreSQL
jeszcze nie jest gotowy.

Skrypt `up.sh` automatycznie sprawdza i naprawia brakujące tabele
po deployu. Jeśli trzeba uruchomić migracje ręcznie:

```bash
kubectl exec deploy/litellm -- sh -c '
  export DATABASE_URL="postgresql://litellm:litellm-poc-password@litellm-postgresql:5432/litellm"
  export DIRECT_URL="$DATABASE_URL"
  prisma db push --schema=/app/schema.prisma --accept-data-loss
'
kubectl rollout restart deployment litellm
```

> `DATABASE_URL` jest też ustawione w `envVars` w Helm values, ale
> `prisma db push` wymaga go jako zmiennej środowiskowej (nie tylko
> w konfiguracji LiteLLM).

## Scenariusz B: baza ma już użytkowników

Po kilku `helm upgrade` LiteLLM może automatycznie stworzyć użytkownika
w bazie PostgreSQL. Od tego momentu env-based login (`UI_USERNAME`/`UI_PASSWORD`)
może być ignorowany – akceptowani są tylko użytkownicy z bazy.

Objawy: po wpisaniu kredencjali ekran logowania wraca do początku
(bez komunikatu o błędzie lub z komunikatem "Invalid credentials").

### Rozwiązanie: stworzenie użytkownika przez API

1. Stwórz użytkownika:

```bash
curl -s -X POST http://EXTERNAL-IP:4000/user/new \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer sk-aigw-master-poc-dev' \
  -d '{
    "user_email": "admin@poc.local",
    "user_role": "proxy_admin",
    "auto_create_key": true
  }' | python3 -m json.tool
```

2. Ustaw hasło (min. 12 znaków, wielka litera, znak specjalny):

```bash
curl -s -X POST http://EXTERNAL-IP:4000/user/update \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer sk-aigw-master-poc-dev' \
  -d '{
    "user_id": "<USER_ID_Z_KROKU_1>",
    "password": "Admin123poc!"
  }' | python3 -m json.tool
```

3. Zaloguj się:
   - **Username**: `admin@poc.local`
   - **Password**: `Admin123poc!`

### Alternatywa: reset bazy PostgreSQL

Dla PoC można usunąć pod PostgreSQL (baza używa emptyDir,
dane nie przetrwają restartu):

```bash
kubectl delete pod litellm-postgresql-0
kubectl rollout restart deployment litellm
```

Po restarcie wracamy do logowania z env vars.

## Sprawdzenie env vars w podzie

```bash
kubectl exec deploy/litellm -- env | grep -E "UI_|MASTER|DATABASE"
```

Oczekiwany wynik:

```
UI_PASSWORD=sk-aigw-master-poc-dev
PROXY_MASTER_KEY=sk-aigw-master-poc-dev
UI_USERNAME=admin
DATABASE_URL=postgresql://litellm:litellm-poc-password@litellm-postgresql:5432/litellm
```

## Rozwiązywanie problemów

| Problem | Przyczyna | Rozwiązanie |
|---------|-----------|-------------|
| "table does not exist" | Migracje Prisma nie przeszły | Sekcja "Migracje bazy danych" powyżej |
| curl 401 na `/login` z JSON | Zły Content-Type | Użyj `/v2/login` z JSON lub `/login` z form data |
| "Loading..." → powrót do loginu | Env-based auth wyłączony | Scenariusz B powyżej |
| "Internal server error" | Brak tabel w bazie | Uruchom `prisma db push` (sekcja migracje) |
| "User has no password set" | User w bazie bez hasła | Ustaw hasło przez `/user/update` |
| Cloud Shell Web Preview: login loop | Proxy stripuje Set-Cookie | Używaj LoadBalancer IP bezpośrednio |
| `<pending>` zamiast External IP | GKE provisionuje LB | Poczekaj 1-2 min, sprawdź `kubectl get svc litellm` |
