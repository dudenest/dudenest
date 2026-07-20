# Direct mode — multi-konto / multi-provider (plan inkrementalny)

**Data**: 2026-07-20 · **Autor**: Dariusz Porczyński · **Status**: plan do wykonania

## Cel
Dziś direct = **jedno** konto Google Drive. Cel: **wiele kont** (kilka Google) + **wielu providerów**
(OneDrive/MS Graph, Dropbox, MEGA…) — odpowiednik relayowego „Cloud Accounts", ale bez relaya.
Bajty plików nadal Flutter→provider wprost; backend trzyma refresh tokeny i mintuje access tokeny.

## Stan wyjściowy (kod)
- `StorageEngine` (interfejs) — `listFiles/uploadFile/downloadFile/deleteFile/getMeta/patchMeta/getFileMap`
  + `thumbnail/preview/original` (ImageProvider). Każdy provider = jedna implementacja.
- `DirectEngine` (Google Drive REST) — gotowy, reużywalny per konto Google.
- Backend `internal/directauth` — OAuth redirect + refresh token; tabela `google_drive_tokens` **PK user_id**
  (1 konto/user) — do uogólnienia.
- HomeScreen — pojedynczy silnik (relay|direct). Galeria konsumuje jeden `StorageEngine`.
- Wzorzec relay: konta kluczowane `type:email` (np. `gdrive:user@gmail.com`), wiele per user.

## Architektura docelowa
### Backend — tabela kont (uogólnienie `google_drive_tokens`)
```sql
CREATE TABLE direct_accounts (
  account_id  STRING PRIMARY KEY,   -- "google:user@gmail.com" (provider:email)
  user_id     STRING NOT NULL,      -- Dudenest Claims.Sub
  provider    STRING NOT NULL,      -- google | onedrive | dropbox | mega
  email       STRING NOT NULL,
  refresh_enc BYTES NOT NULL,       -- AES-256-GCM(refresh_token)
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now(),
  INDEX (user_id)
);
```
Migracja: przepisać 2 istniejące wiersze `google_drive_tokens` → `direct_accounts` (provider=google,
account_id=`google:<email>`); potem `google_drive_tokens` zostawić 1 release jako alias LUB od razu drop
(mało danych). **`google_drive_tokens` nie jest usuwane przed migracją danych.**

### Backend — endpointy (uogólnione z directauth)
- `GET  /api/v1/direct/accounts` → `[{account_id, provider, email}]` usera (requireAuth).
- `GET  /auth/{provider}/connect?token=&return_url=` → redirect OAuth danego providera (uogólniony
  StartDrive; per-provider client_id/secret/scope/authURL z configu). Zapisuje NOWY wiersz (nie nadpisuje).
- `GET  /auth/callback/{provider}` → exchange + userinfo/email + Upsert konta.
- `GET  /api/v1/direct/accounts/{account_id}/token` → mint access token dla konta (refresh; 404 gdy brak).
- `DELETE /api/v1/direct/accounts/{account_id}` → revoke + delete.

Per-provider config w backendzie: klient OAuth (id/secret w env), authURL, tokenURL, userinfo, scope.
Google już jest; OneDrive/Dropbox = kolejne wpisy configu + sekrety + redirect URI w konsoli providera (user).

### Flutter — model kont + agregacja galerii
- `DirectAccount { accountId, provider, email }`; `AccountsService`: `list()` (GET /accounts),
  `connect(provider)` (redirect `/auth/{provider}/connect`), `remove(accountId)`.
- `EngineFactory.forAccount(acc)` → `DirectEngine` (google, token z `/accounts/{id}/token`),
  `GraphEngine` (onedrive), … — każdy `implements StorageEngine`.
- **Galeria**: `AggregateEngine implements StorageEngine` — `listFiles` = merge z wszystkich kont, każdy
  plik otagowany `account_id`; `downloadFile/deleteFile/thumbnail/...` routują do właściwego silnika po
  `account_id` pliku. (MVP: agregacja; alternatywa — dropdown wyboru konta.)
- Ekran „Accounts" (analog relay Cloud Accounts): lista kont, dodaj (redirect per provider), usuń.

## Inkrementy (kolejność)
- **MP1 — Multi-konto Google (fundament)**: backend `direct_accounts` + uogólnione endpointy + migracja +
  testy Go. Flutter: `AccountsService` + ekran Accounts (dodaj/usuń konto Google) + `AggregateEngine`
  (merge wielu DirectEngine). Dowodzi model multi-konto end-to-end, reużywa DirectEngine. **Bez nowego providera.**
- **MP2 — OneDrive (MS Graph)**: `GraphEngine implements StorageEngine` (Graph REST — E0 potwierdził CORS)
  + backend config MS OAuth + redirect URI (Azure, user). Drugi provider dowodzi abstrakcję.
- **MP3+ — Dropbox, MEGA, …**: każdy = engine + config OAuth + konsola providera (user).

## Ryzyka / decyzje
- **Konsola per provider** (user): każdy provider = własny klient OAuth + redirect URI + zgoda. To brama
  per provider (jak Google Console przy auth-parytecie).
- Agregacja vs widok-per-konto (MP1: agregacja z tagiem konta).
- `drive.file` jest per-app-per-konto → każde konto Google widzi swoje pliki tej appki (spójne).
- Sekrety per provider w backend env (jak `GOOGLE_CLIENT_*`).
- Format `account_id` = `provider:email` (czytelne, deterministyczne; kolizja email między providerami wykluczona prefiksem).

## Skąd to wiadomo (kod)
- `lib/core/storage/storage_engine.dart`, `direct_engine.dart`; `lib/core/oauth/google_drive_auth_web.dart`.
- Backend `internal/directauth/{oauth,store,crypto}.go`, tabela `google_drive_tokens` (CRDB `dudenest_hub`, user `backend_drive`).
- Relay wzorzec: `lib/features/storage_accounts/accounts_screen.dart`, `lib/core/oauth/oauth_service.dart`.
