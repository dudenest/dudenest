# Dudenest

![Status](https://img.shields.io/badge/Status-Pre--Alpha-orange) ![Platform](https://img.shields.io/badge/Platform-Flutter-blue) ![License](https://img.shields.io/badge/License-Apache%202.0-green)

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
- A Dudenest account (self-hosted or cloud)

### Development

```bash
git clone https://github.com/dudenest/dudenest.git
cd dudenest
flutter pub get
flutter run
```

### Environment

```bash
cp .env.example .env
# Edit .env with your backend URL and settings
```

## Project Structure

```
lib/
├── core/
│   ├── auth/          # Authentication (JWT, OAuth)
│   ├── network/       # API client, WebSocket, tunnel
│   └── crypto/        # Client-side crypto utilities
├── features/
│   ├── gallery/       # Photo/video timeline grid
│   ├── upload/        # File upload flow
│   ├── player/        # Photo viewer, video player
│   ├── albums/        # Albums and collections
│   ├── storage_accounts/ # Cloud account management ("bricks")
│   ├── relay/         # Relay connection management
│   └── settings/      # App settings
└── shared/
    ├── widgets/       # Reusable UI components
    ├── theme/         # Design system, colors, typography
    └── utils/         # Helpers, formatters
```

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
