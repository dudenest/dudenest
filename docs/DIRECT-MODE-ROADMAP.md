# Direct mode — roadmap pozostałych prac (media, auth parity, multi-provider)

**Data**: 2026-07-19 · **Autor**: Dariusz Porczyński · **Status**: plan / spike (do wdrożenia+weryfikacji)

Kontekst: `DIRECT-MODE-E3-TEST-HANDOVER.md` (stan bazowy). Ten dokument zbiera pozostałe, świadomie
odroczone prace trybu direct po domknięciu parytetu upload/delete. Każda sekcja ma **konkretne
podejście osadzone w istniejącym kodzie** + punkty decyzyjne. Rzeczy web-only (render, GIS) wymagają
weryfikacji runtime na `dudenest.com` (deploy + DevTools) — NIE zamykać na teorii.

---

## 1. Render mediów: avif/heic + wideo — jedno rozwiązanie (blob URL + `HtmlElementView`)

### Problem (potwierdzony objawami usera, do potwierdzenia logami `[dnest-diag]`)
- **avif/heic nie renderują się.** Flutter web/CanvasKit **nie dekoduje** avif/heic. Ścieżka lh3
  (`DirectEngine._thumbBytes`) zawodzi, gdy Drive nie generuje `thumbnailLink` dla avif → fallback na
  surowe bajty → CanvasKit nie dekoduje → pusty kafelek. **lh3 nie jest gwarancją.**
- **wideo w direct** = dziś „coming soon" (`direct_mode_screen._openImage`).

### Rozwiązanie (te same klocki dla obrazu i wideo)
`<img>`/`<video>` przeglądarki **dekodują natywnie** wszystko, co wspiera Chrome (w tym avif/heic/mp4).
Nie da się ustawić nagłówka `Authorization` na `<img>/<video>`, a Drive `alt=media` wymaga `Bearer`
(token w query dla Drive v3 jest zablokowany) → **pobierz bajty tokenem, zrób blob URL, podaj natywnemu
elementowi HTML przez platform view**.

Wzorzec JUŻ istnieje: `lib/features/files/video_player_web.dart` (`HTMLVideoElement` + `ui_web.platformViewRegistry`).
Relay podaje mu URL z tokenem w query (`media_viewer._videoUrl`: `${relay.baseUrl}/files/$id?token=$jwt`).
Direct nie ma takiego endpointu → używa blob URL.

**Kroki implementacji:**
1. **Helper blob (web-only)** — nowy `lib/core/storage/drive_blob_web.dart` (+ stub): `Future<String>
   driveBlobUrl(Uint8List bytes, String mime)` → `web.Blob([bytes.toJS], {type:mime})` →
   `web.URL.createObjectURL(blob)`. Zwolnić przez `revokeObjectURL` w `dispose`.
2. **Obraz avif/heic** — `DriveImageProvider` renderuje przez CanvasKit (nie zdekoduje). Dla formatów
   nierenderowalnych w CanvasKit: komponent `HtmlImageView` (analog `VideoPlayerWidget`) z `<img src=blobURL>`.
   Wybór ścieżki po rozszerzeniu: jpg/png/webp/gif → `Image(DriveImageProvider)` (jak dziś); avif/heic/heif
   → `HtmlImageView(blob)`. Bajty: `DirectEngine.downloadFile` (alt=media, Bearer) — dla miniatur lepiej
   lh3 (mniejsze), ale gdy lh3 brak (avif) → oryginał do bloba.
3. **Wideo** — reużyj `VideoPlayerWidget`, ale podaj **blob URL** zamiast token-URL relaya. W
   `direct_mode_screen._openImage`: jeśli `_isVideo(name)` → pobierz bajty → blob → `VideoPlayerWidget(videoUrl: blob)`.
   Uwaga: `headers` nieużywane na web (pole zostaje dla zgodności sygnatury).

### 🔴 Tradeoff (decyzja)
Blob = **pełne pobranie pliku do RAM** przed odtworzeniem. OK dla zdjęć (kilka MB) i krótkich klipów;
**złe dla dużych wideo** (GB). Opcje dla dużych wideo (późniejsze):
- (a) `MediaSource` + Range-requests (streaming z tokenem) — złożone, ale prawdziwy streaming;
- (b) tymczasowo: limit rozmiaru na blob-playback + komunikat „pobierz, by odtworzyć" dla dużych.
MVP: blob dla wszystkiego + świadomy limit rozmiaru z jasnym komunikatem.

### Weryfikacja (web-only)
Deploy gałęzi → dudenest.com → wgraj świeży avif + krótkie mp4 → kafelek+podgląd renderują; wideo gra.
Testy jednostkowe: routing (jaki komponent dla jakiego rozszerzenia) + stub blob; sam render/playback = runtime.

---

## 2. Auth parity — „/photos od razu jak relay" (sufit GIS + decyzja refresh-token)

### Ustalone
- Relay pokazuje /photos natychmiast, bo trzyma **server-side refresh token** (authorization-code flow,
  offline access) — token odnawiany w tle, bez udziału usera.
- Direct używa **GIS token model**: access token ~1h, **BEZ refresh tokena**; ciche re-grant (`prompt:''`)
  **blokowane przez Chrome przy 2.+ loginie** (3rd-party cookies). To dokładnie objaw usera („po drugim
  loginie nie łączy od razu").
- Do potwierdzenia logami `[dnest-diag]`: `about.get` pod scope `drive.file` prawdopodobnie NIE zwraca
  `emailAddress` → weryfikacja izolacji (`driveEmail == userEmail`) gate'uje ZAWSZE, nawet gdy silent OK.
  Jeśli tak — do weryfikacji konta dołożyć **non-sensitive scope `openid email`** (bez CASA; zmienia ekran
  zgody) albo `userinfo` endpoint.

### 🔴 DECYZJA PRODUKTOWA (usera)
- **A) Zostać przy GIS**: naprawić weryfikację (openid email), ale „natychmiast przy KAŻDYM loginie"
  pozostaje nieosiągalne przy restrykcjach cookies — czasem 1 klik „Connect" na sesję.
- **B) Authorization-code flow + refresh token**: pełny parytet z relay (zawsze natychmiast), ale
  **backend uczestniczy w OAuth direct i trzyma poświadczenie Google** — częściowo cofa ideę „direct =
  bez serwera na ścieżce". Wymaga: endpoint backendu na code-exchange (drive.file, offline), bezpieczne
  przechowanie refresh tokena (per user, szyfrowane), odświeżanie access tokena.

Bez decyzji A/B nie ma sensu dalej „poprawiać" silent — GIS strukturalnie nie zrobi tego, co refresh token.

---

## 3. Multi-account / multi-provider w direct (prośba usera: „powinno być zaplanowane")

Dziś direct = **jedno konto Google Drive** (`drive.file`). Relay ma multi-provider przez „Cloud Accounts".
E0 (plan relay-removal) potwierdził empirycznie: **11/13 providerów działa wprost z przeglądarki przez CORS**
(GDrive, GPhotos, MS Graph/OneDrive, Dropbox, Box, pCloud, MEGA, Filen, Koofr, Storj; wypadają B2 + Icedrive).

### Architektura docelowa
- `StorageEngine` już jest abstrakcją per-backend. Multi-account = **lista `StorageEngine`** (po jednym na
  podłączone konto) + warstwa agregująca (merge list plików, routing operacji do właściwego enginu po
  `account_id`).
- Każdy provider = własny OAuth (browser, PKCE/GIS-equiv) + własny klient REST w Dart (jak `DirectEngine`
  dla Drive). To **N implementacji `StorageEngine`** — największy koszt.
- UI: ekran „Accounts" (analog relay Cloud Accounts) — dodaj/usuń konto, per-account status; galeria
  agreguje lub filtruje po koncie.

### Etapy (propozycja)
1. **Multi-account Google** (najprościej — ten sam `DirectEngine`, różne tokeny/`account_id`): model konta
   + przechowanie per-account tokenu (per-uid, jak dziś) + agregacja list. Rozwiązuje „więcej kont Google".
2. **OneDrive** (MS Graph — CORS OK): `GraphEngine implements StorageEngine`.
3. **MEGA / Dropbox / …**: kolejne enginy wg priorytetu.
- Zależność: decyzja auth (§2) wpływa na trwałość tokenów per-provider.

To duży blok (osobne sesje per provider). Ten dokument = mapa; kolejność i zakres do ustalenia z userem.

---

## Stan i pozycje otwarte
- ✅ Zrobione (osobna gałąź `feat/direct-parity-upload-delete`, PR #16, niezmergowane): upload+delete
  parytet, UI angielski, Photos filtruje po rozszerzeniu (pdf→Files), Photos≠Files (`ValueKey` per folder),
  mimeType przy uploadzie, `driveAccountEmail`, szkielet cichego auto-connect (z logami diag).
- 🔬 Czeka na dane: logi `[dnest-diag]` z konsoli usera (avif thumbnailLink? / silent+driveEmail?).
- 🔴 Czeka na decyzję usera: §2 A/B (refresh token), §3 kolejność providerów.
- ⏭️ Do wdrożenia po decyzjach: §1 render mediów (avif/wideo przez blob+HtmlElementView).
