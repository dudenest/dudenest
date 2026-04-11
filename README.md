# Dudenest

![Version](https://img.shields.io/badge/Version-v0.3.0-blue) ![Status](https://img.shields.io/badge/Status-Alpha-orange) ![Platform](https://img.shields.io/badge/Platform-Flutter-blue) ![License](https://img.shields.io/badge/License-Apache%202.0-green) ![Last Update](https://img.shields.io/badge/Update-2026--04--08-lightgrey)

**Your files. Your blocks. Your cloud.**

Dudenest is an open-source photo, video and file storage platform — a privacy-first alternative to Google Photos and Apple Photos. Your files are never stored on our servers. Instead, they are split into encrypted blocks distributed across free cloud accounts you control.

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
2. **Click a photo** — Relay downloads encrypted blocks from your cloud accounts and decrypts locally
3. **Upload a file** — split into 5-10 MB encrypted blocks, distributed with Reed-Solomon erasure coding (6+3: lose 3 accounts, still recover everything)
4. **Zero knowledge** — Dudenest servers never see your files or decryption keys

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

### v0.4.0 — 2026-04-11 — Security Hardening + Diagnostics
- 🔐 **Relay API Security**: Every request to Relay (including `Image.network` for thumbnails and full images) now requires a `Bearer <JWT>` authorization header.
- 🔧 **RelayClient Hardening**: Improved error handling with `RelayException`. The app now verifies `Content-Type: application/json` before parsing.
- 🧪 **Automated CI/CD Tests**: Added unit and widget tests for Relay authentication and error states. Integrated `flutter test` into GitHub Actions.
- 🐛 **UI Overflow Fix**: Fixed `RenderFlex` overflow on `LoginScreen` for smaller screens.
- 🛠️ **Diagnostic UI**: Added `_ErrorDisplay` widget showing HTTP status codes and response bodies for easier infrastructure debugging.

### v0.3.0 — 2026-04-08 — OAuth E2E + Cloud Accounts
- 🔐 **OAuth E2E fixed**: `web/auth` callback now uses localStorage (flutter_web_auth_2 v4 new-tab flow)
- 🔐 **Fixed web/auth MIME**: nginx served file as `application/octet-stream` (download) → now HTML
- 📱 **Method E**: In-app WebView with JS auto-fill for Google OAuth (Android/iOS/desktop)
- ☁️ **Multi-account support**: add and manage multiple Google Drive accounts
- 📊 **Storage stats**: used/total GB bar in Cloud Accounts screen + badge in Files AppBar
- 🔗 **Social links**: GitHub + Discord icons in login footer; Community section in Settings
- 🎨 **Brand icons**: `font_awesome_flutter` — GitHub, Discord, YouTube, Facebook, X

### v0.2.1 — 2026-04-07 — Thumbnails + Key Management
- 🖼️ Thumbnails: `GET /files/{id}/thumbnail` — lazy-generated 200×200 JPEG, GlusterFS cache
- 🔑 BIP39 mnemonic key management: `relay setup` (generate) + `relay recover` (re-derive)
- 📧 Email via Resend.com: relay sends encryption key mnemonic to owner on setup
- 🔧 `relay.service` systemd unit on relay-poc VM

### v0.2.0 — 2026-04-07 — OAuth & UI Milestone
- 🔐 Google OAuth2 login (end-to-end)
- 🔐 GitHub OAuth2 login
- 🌟 Animated starfield login background
- 🗂️ Files: grid/list/long-names view modes, fullscreen viewer with pinch-to-zoom
- ☁️ Cloud Accounts: step-by-step add flow (browser screenshot + field fill)

## Contributing

Dudenest is open source under Apache 2.0. Contributions welcome!

- [Contributing Guide](docs/CONTRIBUTING.md)
- [Architecture Overview](docs/architecture/OVERVIEW.md)
- [Design System](docs/design/DESIGN_SYSTEM.md)

## Security

Files are split into 5-10 MB blocks, encrypted with AES-256-GCM, and distributed using Reed-Solomon erasure coding before reaching any cloud provider. The Dudenest backend only sees metadata (filenames, dates, tags) — never file content or encryption keys.

Security reports: security@dudenest.com

## License

Apache License 2.0 — see [LICENSE](LICENSE)

---

**Author**: Dariusz Porczyński
**Organization**: https://github.com/dudenest
