# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
