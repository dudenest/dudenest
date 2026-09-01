# Dudenest

[![Version](https://img.shields.io/github/v/release/dudenest/dudenest?color=blue&label=Version)](https://github.com/dudenest/dudenest/releases/latest) [![Release Date](https://img.shields.io/github/release-date/dudenest/dudenest?color=lightgrey&label=Released)](https://github.com/dudenest/dudenest/releases/latest) ![Last Update](https://img.shields.io/badge/Update-2026--05--18-orange) ![Status](https://img.shields.io/badge/Status-Alpha-orange) ![Platform](https://img.shields.io/badge/Platform-Flutter-blue) ![License](https://img.shields.io/badge/License-Apache%202.0-green) ![Logging](https://img.shields.io/badge/Logging-Graylog%20GELF-9cf)
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fdudenest%2Fdudenest.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fdudenest%2Fdudenest?ref=badge_shield)

**Your files. Your cloud. Your privacy.**

Dudenest is an open-source photo, video and file storage platform — a privacy-first alternative to Google Photos and Apple Photos. Your files are never stored on our servers. Instead, they are stored as replicas directly on free cloud accounts you control (Google Drive, MEGA, OneDrive, etc.).

## How It Works

```
┌─────────────────┐    WireGuard Tunnel    ┌──────────────────────────┐
│   Dudenest App  │ ◄───────────────────► │  Relay (your Raspberry Pi)│
│  (this repo)    │                        │  dudenest-relay           │
└─────────────────┘                        └──────────────────────────┘
         │                                           │
         ▼                                           ▼
┌─────────────────┐                        ┌──────────────────────────┐
│ Dudenest Cloud  │                        │  Your Cloud Accounts     │
│  (metadata only)│                        │  Google Drive, MEGA,     │
│  dudenest-backend│                       │  OneDrive, pCloud...     │
└─────────────────┘                        └──────────────────────────┘
```

1. **You see thumbnails** — stored locally on your Relay for instant browsing
2. **Click a photo** — Relay downloads the file from your cloud account (tries Main, falls back to Backup replica)
3. **Upload a file** — stored as-is on up to 2 of your cloud accounts (1 copy per provider); no encryption at storage level — HTTPS secures the transport
4. **Privacy-first** — Dudenest servers never see your file content

## Features

- **Photo and video gallery** — 4 layout modes: Justified (Google Photos-style), Masonry (Pinterest), Square grid, List
- **Media viewer** — fullscreen viewer with swipe/keyboard navigation, pinch-to-zoom, progressive loading (LQIP → 800px preview → original)
- **Timeline navigation** — files grouped by EXIF date; right-side scrubbar for fast jumping
- **Video support** — inline playback, video thumbnails in all gallery modes
- **Gallery settings** — per-user preferences: layout, row height, column count, date grouping (persisted)
- Automatic backup from mobile
- Face/location/tag search _(planned)_
- File sharing via secure links _(planned)_
- Storage account management ("bricks")
- Cross-platform: iOS, Android, Web, Windows, macOS, Linux

## Architecture

This is the **client application** (Flutter). For other components:

| Component | Repo | Visibility |
|-----------|------|-----------|
| **dudenest** (this) | Client Flutter app | Public |
| [dudenest-relay](https://github.com/dudenest/dudenest-relay) | Relay Go agent | Public |
| [dudenest-backend](https://github.com/dudenest/dudenest-backend) | SaaS API (Go) | Public |
| dudenest-infra | NETOL infrastructure | Private |

## Getting Started

> **Note**: Dudenest is in pre-alpha. These instructions are for developers.

### Requirements
- Flutter 3.x
- A running Dudenest Relay (see [dudenest-relay](https://github.com/dudenest/dudenest-relay))
- A Dudenest account — sign in with Google, GitHub, or Apple

### Development

```bash
git clone https://github.com/dudenest/dudenest.git
cd dudenest
flutter pub get
flutter run -d chrome      # web
flutter run                # native (iOS/Android/desktop)
```

### Local dev with relay

```bash
# Forward relay port over SSH tunnel
ssh -L 8086:192.168.0.119:8086 root@10.51.1.101

# The app uses https://relay.dudenest.com in production
# For local testing, change _relayUrl in lib/main.dart to http://localhost:8086
```

## Media Playback

**Media files (photos, videos) must be displayed and played directly within the app.** This is a core product requirement.

### Image Loading Pipeline

Relay serves three image tiers; the app loads them progressively:

| Tier | Endpoint | Size | Purpose |
|------|----------|------|---------|
| **LQIP** | Inline in `GET /files` response (`lqip` field) | 20 px wide base64 JPEG | Instant blur placeholder |
| **Thumbnail** | `GET /files/{id}/thumbnail` | 200×200 px square JPEG | Gallery tiles |
| **Medium preview** | `GET /files/{id}/preview` | 800 px longest-side JPEG | Fullscreen fast load |
| **Original** | `GET /files/{id}` | Full resolution | Zoom / download |

Progressive loading sequence in MediaViewer: LQIP (rendered from memory) → 800 px preview (300 ms AnimatedOpacity crossfade) → original (active page only).

Relay stores thumbnails and previews at `~/.config/dudenest/thumbnails/`:
- `<fileID>.jpg` — 200×200 square thumbnail
- `<fileID>_medium.jpg` — 800 px aspect-preserving preview
- `<fileID>.lqip` — base64 JPEG data-URI (20 px placeholder)
- `<fileID>.dims` — width, height, taken_at sidecar

### Gallery View Modes

The file browser supports four gallery layouts (selectable via `tune` icon → Gallery settings):

| Mode | Description | Best for |
|------|-------------|---------|
| **Justified** | Google Photos-style rows; correct aspect ratio; configurable row height | Photo browsing |
| **Masonry** | Pinterest-style staggered columns; 2–4 configurable columns | Mixed media |
| **Square** | Fixed 3-column grid | Quick scan |
| **List** | Name + size + thumbnail | Files / documents |

### File Browser Modes

Three top-level modes (AppBar icons):
- **Gallery** — the gallery view modes above
- **List** — compact list with file icons
- **Long names** — full filenames with wrapping

## Authentication

Users authenticate via OAuth2 (Google, GitHub, Apple). The flow:

```
1. User taps "Continue with Google"
2. App redirects to: https://api.dudenest.com/auth/google?return_url=https://dudenest.com
3. User authorizes on Google
4. Backend redirects to: https://dudenest.com?token=JWT&user=base64(JSON)
5. App reads token from URL, stores in localStorage (SharedPreferences)
6. URL cleaned via history.replaceState
```

Token: HS256 JWT, 30-day expiry, signed with `JWT_SECRET`.
User data stored in `localStorage` as `auth_token` + `auth_user` (base64 JSON).

## Project Structure

```
lib/
├── core/
│   ├── auth/          # OAuth service, JWT model, web utils (conditional import)
│   └── network/       # RelayClient (HTTP to relay)
├── features/
│   ├── auth/          # LoginScreen (Google / GitHub / Apple buttons)
│   ├── upload/        # UploadScreen with multi-file + progress animation
│   ├── relay/         # RelayScreen (file browser)
│   └── storage_accounts/ # AccountsScreen (Google Drive accounts)
└── main.dart          # DudenestApp, HomeScreen, SettingsScreen
test/
├── unit/
│   ├── user_model_test.dart   # AuthUser fromJson/toJson
│   └── relay_client_test.dart # RelayClient HTTP calls
└── widget/
    ├── login_screen_test.dart    # OAuth button rendering
    ├── upload_screen_test.dart   # Upload flow
    ├── accounts_screen_test.dart # Accounts list states
    └── relay_screen_test.dart    # File browser
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full version history.

## Contributing

Dudenest is open source under Apache 2.0. Contributions welcome!

- [Contributing Guide](docs/CONTRIBUTING.md)
- [Architecture Overview](docs/architecture/OVERVIEW.md)
- [Design System](docs/design/DESIGN_SYSTEM.md)

## Security

Files are stored as replicas on your own cloud accounts (Google Drive, MEGA, OneDrive, etc.) — up to 2 copies, each on a different provider. Files go directly from your Relay to your cloud accounts via HTTPS; the Dudenest backend only sees metadata (filenames, dates, tags) — never file content.

Security reports: security@dudenest.com

## License

Apache License 2.0 — see [LICENSE](LICENSE)

---

**Author**: Dariusz Porczyński
**Organization**: https://github.com/dudenest


[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fdudenest%2Fdudenest.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fdudenest%2Fdudenest?ref=badge_large)