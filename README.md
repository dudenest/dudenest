# Dudenest

[![Version](https://img.shields.io/github/v/release/dudenest/dudenest?color=blue&label=Version)](https://github.com/dudenest/dudenest/releases/latest) [![Release Date](https://img.shields.io/github/release-date/dudenest/dudenest?color=lightgrey&label=Released)](https://github.com/dudenest/dudenest/releases/latest) ![Last Update](https://img.shields.io/badge/Update-2026--05--17-orange) ![Status](https://img.shields.io/badge/Status-Alpha-orange) ![Platform](https://img.shields.io/badge/Platform-Flutter-blue) ![License](https://img.shields.io/badge/License-Apache%202.0-green) ![Logging](https://img.shields.io/badge/Logging-Graylog%20GELF-9cf)

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

- Photo and video gallery (timeline, albums, search)
- Automatic backup from mobile
- Face/location/tag search
- File sharing via secure links
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

### Thumbnails

| Platform | Thumbnail source | Persistent cache |
|----------|-----------------|-----------------|
| **Web (browser)** | `GET /files/{id}/thumbnail` | Browser HTTP cache |
| **Android / iOS** | `GET /files/{id}/thumbnail` | Local device storage (TODO) |
| **Desktop** | `GET /files/{id}/thumbnail` | Local device storage (TODO) |

Relay generates 200×200 JPEG thumbnails on upload and caches them at `~/.config/dudenest/thumbnails/`.

### View Modes

The file browser supports three modes:
- **List** — truncated names, file/image/video icons
- **Long names** — full filenames (wrapping), no truncation
- **Thumbnails** — 160×160px grid; images via `Image.network`, videos/others as icon

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
