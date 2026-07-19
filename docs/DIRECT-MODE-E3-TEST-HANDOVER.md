# Direct Mode (E3) — stan, bezpieczeństwo i procedura testu izolacji

**Data**: 2026-07-19 · **Autor**: Dariusz Porczyński · **Status**: ✅ WŁĄCZONE (beta), izolacja ZWERYFIKOWANA

> **✅ WYNIK WERYFIKACJI (2026-07-19)** — test w 2 izolowanych profilach (dwie maszyny, każda jedno konto
> Google) przeszedł: banner debug pokazał `Dudenest email == Drive email` na obu (darek↔darek,
> visaroy↔visaroy), zero „⚠ RÓŻNE KONTA", żaden profil nie widział plików drugiego. Punkt 2
> („Settings=A, Photos=B jednocześnie") **NIE odtworzył się** na izolowanych maszynach → był artefaktem
> współdzielonej przeglądarki (login Dudenest cicho bierze domyślne konto Google — §2, osobny wątek od
> direct mode), nie wyciekiem tokenu Drive. **Direct włączony** (`kDirectModeEnabled=true`), banner debug
> i brama `?e3ctest=1` USUNIĘTE. Poniższa procedura testu zachowana jako referencja na przyszłe zmiany.

Ten dokument jest handoverem dla agenta kontynuującego pracę nad „direct mode" (Photos/Files czytają
Google Drive bezpośrednio, bez relaya). **Przeczytaj przed dotknięciem czegokolwiek w `lib/features/files/direct_mode_screen.dart`, `lib/core/oauth/google_drive_auth_web.dart`, `lib/core/storage/direct_engine.dart` lub flagi `kDirectModeEnabled` w `lib/main.dart`.**

## 1. Stan skrótowo
- Direct mode jest **w pełni zaimplementowany** (toggle w Settings, DirectEngine=Drive REST, upload, render), ale **UKRYTY na prod**: `const kDirectModeEnabled = false` (`main.dart`). Toggle nie pokazuje się, HomeScreen wymusza relay.
- **Relay** = domyślny, produkcyjny, nietknięty. Direct to osobna ścieżka „obok relaya".
- **Powód ukrycia**: izolacja między kontami użytkowników **niezweryfikowana** (patrz §3).

## 2. DWA osobne przepływy OAuth (źródło pomyłek)
1. **Login Dudenest** — „Login with Google" → `api.dudenest.com/auth/google` (backend). **NIE wymusza wyboru konta** — bierze domyślne konto Google przeglądarki. Daje JWT + `AuthUser{id,email,provider}` (`AuthService`).
2. **Connect Drive** (direct mode) — Google Identity Services (GIS) token model, scope `drive.file`, klient `google_config.dart`. Od 2026-07-19 z `prompt:'select_account'` → zawsze pyta, które konto Google.

To są NIEZALEŻNE tożsamości. Direct mode wiąże token Drive z `AuthService.user.id` (login Dudenest), NIE z kontem Google Drive.

## 3. Historia bezpieczeństwa — co naprawione, co NIE
- **Wprowadzony bug (i naprawiony)**: persystencja tokenu Drive w localStorage (dodana opportunistycznie) zapisywała token pod stałym kluczem, bez powiązania z userem, bez czyszczenia przy wylogowaniu → po zmianie konta Dudenest ekran auto-łączył się CUDZYM Drive.
- **Naprawa kierunek-1 (potwierdzona przez usera)**: token wiązany z `AuthService.user.id`, używany tylko gdy `storedUid==currentUid`; `clearDriveToken()` przy Sign out; DEMO bez persystencji. (`google_drive_auth_web.dart`.)
- **🔴 NIEZWERYFIKOWANE — punkt 2**: user zaobserwował „Settings pokazuje konto A, Photos pokazuje dane konta B — jednocześnie". Dwie interpretacje: (A) nieświeży `AuthService.user` w UI, (B) realny wyciek (sesja=A, Drive=B). **Nierozstrzygnięte.** Cała izolacja stoi na `AuthService.user` — jeśli ten stan bywa nieświeży, wiązanie jest niepewne.
- Środowisko usera (JEDNA przeglądarka, OBA konta Google, czyszczone cookies, wiele cykli login/logout) **nie może udowodnić izolacji**.

## 4. Brama testowa `?e3ctest=1` + banner debug
- `directModeEnabled()` w `main.dart` = `kDirectModeEnabled || (?e3ctest=1 w URL)`. Prod domyślnie ukryty; `https://dudenest.com/?e3ctest=1` włącza toggle direct do KONTROLOWANEGO testu (bez eksponowania direct wszystkim).
- **Banner debug** (`DirectModeScreen._debugBanner`): pokazuje `Dudenest: <email> | Drive: <email>` (Drive z `DirectEngine.driveAccountEmail()` → Drive `/about`). „⚠ RÓŻNE KONTA" gdy się różnią. To narzędzie do rozstrzygnięcia punktu 2. **Usunąć/schować przy włączaniu direct na prod.**

## 5. PROCEDURA TESTU IZOLACJI (2 profile) — WYMAGANA przed `kDirectModeEnabled=true`
Cel: udowodnić, że user Dudenest X nigdy nie widzi danych usera Y bez świadomego podłączenia konta Y.

1. **Dwa izolowane konteksty**: dwa profile Chrome (Menu → profile) ALBO dwie maszyny. Każdy zalogowany do **DOKŁADNIE JEDNEGO** konta Google. Profil A = tylko konto A; Profil B = tylko konto B.
2. W obu otwórz `https://dudenest.com/?e3ctest=1`.
3. **Profil A**: Login Dudenest (konto A) → Settings → włącz „Tryb direct" → Photos → Connect → wybierz konto A. Banner MUSI pokazać `Dudenest = Drive` (to samo konto A), bez „⚠ RÓŻNE KONTA". Wgraj plik. Zapamiętaj co widać.
4. **Profil B**: to samo z kontem B. Banner `Dudenest=B, Drive=B`.
5. **Cross-check**: Profil A NIGDY nie widzi plików B i odwrotnie. Banner nigdy nie pokazuje sesja=A + Drive=B.
6. **Odtwórz punkt 2**: w jednym profilu wyloguj i zaloguj drugie konto Dudenest (jeśli profil ma dostęp) → obserwuj banner: czy `AuthService.user.email` (Dudenest w bannerze) zgadza się z Settings i z pokazywanymi danymi. Jeśli banner pokaże sesja=A + Drive=B → **realny wyciek (B), NIE włączać**.
7. Jeśli wszystko czyste → decyzja o modelu tożsamości (§6) → dopiero `kDirectModeEnabled=true` + usunięcie bannera debug.

## 6. Decyzja projektowa do podjęcia (przed włączeniem)
Czy konto Google Drive ma być **WYMUSZone == konto Dudenest** (dla loginów przez Google)? Dziś NIE — user może podłączyć dowolny Drive. Opcje: (a) zostaw (user choice, ale wymagaj select_account — zrobione); (b) wymuś dopasowanie email Drive == email Dudenest dla providera Google (nie dotyczy GitHub/Apple). To wpływa na to, czy punkt 2 to bug czy feature.

## 7. Uwagi
- Warstwa GIS/token jest **web-only** (`google_drive_auth_web.dart`; nie-web = stub). `flutter test` (VM) testuje STUB → logika izolacji ma **zero pokrycia automatycznego**. Weryfikacja tylko manualna/runtime → tym bardziej wymaga kontrolowanego środowiska.
- Direct mode **persystuje token drive.file w localStorage** (świadoma decyzja, ~1h TTL, jak JWT aplikacji). Klucze: `drive_access_token`, `_exp_ms`, `_uid`.
- `localhost` NIE jest autoryzowanym originem GIS (`google_config.dart`: dudenest.com + app.dudenest.com) → test tylko na wdrożonym buildzie.
- Pełna narracja: `~/.AI/dudenest-application/session-2026-07-15-relay-removal-flutter-first-analysis.md` (sekcje 2026-07-18/19) + `STATE.md`.
