# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.7.1] — 2026-07-13

### Fixed
- **Upload button now in every section.** The Photos and Files screens only offered an upload action in their empty state — once files existed you had to switch to the separate Upload tab. Added a persistent "Upload" `FloatingActionButton` to both sections (hidden only during multi-select). Refreshes the file list on return.

## [0.7.0] — 2026-07-12 — Method 3 Remote-Hand login, Demo mode & tile cache

### Added
- **Relay-assisted login (method 3):** a native dynamic form drives a vanilla Chromium on the relay (CDP-free, undetectable) to sign into Google — handles email/password, 2FA phone/SMS, send-code, captcha, the "unverified app" warning and consent, with per-field re-prompts on errors. Credentials are sealed to the relay (zero-knowledge). Success screen offers "Add Next Account" / "Finish"; the working state shows a progress bar.
- **Demo mode:** "Try DEMO — no sign-in needed" on the login screen (+ `?demo=1` deep link) starts a shared throwaway session; a pulsing green DEMO badge marks it and only relay-assisted login is offered. The sandbox resets periodically.
- Flutter now loads a local tile manifest snapshot before syncing with relay, so Photos/Files can render immediately after the first successful sync.
- Relay client supports `GET /files/manifest?since=<revision>` with fallback to legacy `GET /files`.
- Gallery settings expose configurable local tile cache limits and Flutter thumbnail memory LRU limits.
- Settings duplicates the gallery cache/LRU controls so limits can be changed outside `/Photos`.

### Changed
- Login buttons renamed to "Login with Google/GitHub/Apple"; the app version chip now shows the released version instead of the commit hash.
- Photos view toggle drops the redundant "Long names" mode; cloud-account tiles now reorder only by dragging their handle so the list scrolls normally.
- Photos and Files share the same cached manifest; tab filtering remains local via the existing `folder` field.
- Manifest fallback also handles old relays that return HTTP 500 by treating `manifest` as a file ID.
- `/Files` now shows all cloud-indexed files as a plain list with icon, name, extension, size, and file ID instead of the Photos gallery layout.
- File-screen errors include a Back action so a failed preview/download no longer traps the user on Retry only.

---

## [0.6.0] — 2026-05-18 — Gallery UI & Media Viewer Overhaul

### Added
- **MediaViewer — fullscreen photo & video viewer**
  - Swipe left/right to navigate between files (PageView)
  - Keyboard ← → to navigate, Escape to close
  - Mouse-hover-reveal overlay: navigation arrows (◀ ▶), title bar with download/delete/info, page counter
  - Progressive loading: LQIP blur placeholder → 800px preview (AnimatedOpacity crossfade) → original full resolution
  - Pinch-to-zoom via `InteractiveViewer` (`panEnabled: _zoomed` — at 1× scale PageView captures swipes; at zoom > 1.05× image panning activates)
  - Video inline playback with `VideoPlayer` widget
  - Info panel: filename, resolution, EXIF date, file size
  - Auto-hide overlay: 4 s for photos, 8 s for videos; re-shown on tap/mouse-move
- **Gallery layout system — 4 modes**
  - **Justified** (default) — Google Photos-style rows with correct aspect ratio; target row height configurable 120–320 px
  - **Masonry** — Pinterest-style staggered columns; column count 2–4 configurable
  - **Square** — 3-column fixed grid (original mode preserved)
  - **List** — file list with thumbnail, name, size
- **Gallery settings bottom sheet** — `tune` icon in AppBar (gallery mode only)
  - Visual layout picker: 4 animated card buttons with icons; selected card highlighted
  - Row height slider (Justified mode)
  - Column count slider (Masonry mode: 2/3/4)
  - Toggle: Group by date
  - Toggle: Show date headers
  - Toggle: Show timeline scrubbar
  - All settings persisted via `SharedPreferences`
- **DateScrubbar** — 30 px vertical right-side timeline for fast scroll navigation (Justified mode only); year/month markers; tap or drag to jump
- **Date grouping** — files grouped by EXIF `taken_at`; fallback to `created` upload timestamp; newest group first
- **Video thumbnail overlays** — play icon (▶) overlay on video tiles in all grid modes

### Fixed
- **Justified grid: all tiles were 1:1 squares** — thumbnail decoder (200×200 square JPEG) was used for ratio detection → always 1.0; replaced with LQIP-based AR detection via `dart:ui.instantiateImageCodec`; falls back to `width`/`height` from API metadata
- **Masonry infinite scroll** — `ClampingScrollPhysics` added; DateScrubbar restricted to Justified mode only (no stale offset interference); `_groupOffsets` cleared and scroll reset to 0 on mode switch
- **Gallery settings not visible** — replaced hidden `PopupMenuButton` with `tune` icon + bottom sheet; layout options now clearly labeled with icons
- **Square LQIP (relay-side fix applied)** — old files now get correct LQIP via relay lazy sidecar generation

---

## [0.5.0] - 2026-05-14

### Added
- **Per-user relay routing** — app automatically fetches user's relay URL and token from `GET /api/v1/relays`; no manual relay configuration needed
- **Relay Management screen** — Settings → My Relays & Backups: view registered relays, backup status, relay URL
- **Storage Strategy toggle** — Settings: switch between Replica (Main + 1 Backup) and legacy Chunking modes; persisted in SharedPreferences (Replica is current default)
- **Storage Visualizer** — Cloud Accounts screen: pie/bar charts of storage usage per Google Drive account (fl_chart)
- **File count per account** — Cloud Accounts screen shows `file_count` returned by relay
- **Relay URL override** — Settings: manually set custom relay URL (dev/self-hosted setups)

### Security
- **Layer 3 relay token** — `X-Relay-Token` (short-lived HMAC, 1h TTL) sent on all relay requests; generated server-side per user
- **Bearer token on all requests** — `RelayClient` includes `Authorization: Bearer <jwt>` on every relay API call

### Fixed
- **Cold-start 403 eliminated** — app now waits for relay token before rendering Files screen; shows loading indicator during token fetch instead of 403 error
- **Relay token expiry 403 fixed** — `Timer.periodic(50min)` automatically refreshes token before 1h TTL expires; additional refresh triggered on tab switch to Files
- **StorageVisualizer labels** — use account email instead of provider type (`gdrive`) as chart labels; all accounts were indistinguishable before
- **StorageVisualizer empty state** — providers set immediately on load; failed file maps skipped instead of blocking entire view

---

## [0.4.1] - 2026-04-11

Maintenance and ecosystem version sync.

---

## [0.4.0] - 2026-04-09

### Added
- **NovNC auth implementation** — authentication layer for VNC sessions
- **NovNC crop/UX improvements** — improved viewport and user experience

### Security
- **Authorization headers on Image.network** — all image requests now include Bearer token

### Fixed
- **RelayClient syntax error** — resolved crash on startup

---

## [0.3.0] - 2026-04-08

### Added
- **OAuth E2E flow** — complete Google OAuth login with callback handling
- **Cloud Accounts screen** — view and manage connected Google Drive accounts
- **JWT Bearer authentication** — RelayClient sends JWT on all requests

---

## [0.2.0] - 2026-04-07

### Added
- **OAuth login** — Google OAuth via backend redirect flow
- **UI foundations** — bottom navigation, theme switching (light/dark/system), shared preferences

---

## [0.1.0] - 2026-03-30

### Added
- Initial Flutter app scaffold
- Relay client networking layer
- Upload screen (placeholder)
- Files/Relay screen (placeholder)
