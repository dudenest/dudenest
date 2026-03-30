# Dudenest Architecture Overview

**Author**: Dariusz Porczyński
**Date**: 2026-03-30

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      DUDENEST ECOSYSTEM                          │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │              DUDENEST SAAS CLOUD (NETOL)                   │  │
│  │                                                            │  │
│  │  api.dudenest.com → HAProxy(ns2) → Traefik → Backend      │  │
│  │                                                            │  │
│  │  Backend stores:                                           │  │
│  │  • User accounts (email, password hash)                    │  │
│  │  • File metadata (name, date, GPS, tags, MIME)             │  │
│  │  • Thumbnail references (IDs — thumbnails on Relay)        │  │
│  │  • Relay registrations (which Relay belongs to which user) │  │
│  │  • Block counts, erasure scheme (no actual keys/blocks)    │  │
│  │                                                            │  │
│  │  headscale.netol.io → WireGuard coordination (existing)   │  │
│  └────────────────────────────────────────────────────────────┘  │
│                          │ HTTPS (metadata)                      │
│                          │ WireGuard (signaling via Headscale)   │
│  ┌───────────────────────┼────────────────────────────────────┐  │
│  │     DUDENEST CLIENT APP (this repo — Flutter)              │  │
│  │                       │                                    │  │
│  │  Platforms: iOS, Android, Web, Win, macOS, Linux           │  │
│  │                       │ WireGuard tunnel                   │  │
│  └───────────────────────┼────────────────────────────────────┘  │
│                          │                                       │
│  ┌───────────────────────┼────────────────────────────────────┐  │
│  │     RELAY (user's Raspberry Pi — dudenest-relay)           │  │
│  │                       │                                    │  │
│  │  • Block Map DB (SQLite): block_id → cloud account + path  │  │
│  │  • Thumbnail Cache: local thumbnails for instant scroll    │  │
│  │  • Block Engine: AES-256-GCM + Reed-Solomon                │  │
│  │  • Cloud Connectors: Google Drive, MEGA, OneDrive...       │  │
│  │  • Decryption keys: ONLY here, never leave Relay           │  │
│  └─────────────────────────────────────────┬──────────────────┘  │
│                                            │ HTTPS per provider   │
│  ┌─────────────────────────────────────────┼──────────────────┐  │
│  │              USER'S CLOUD ACCOUNTS      │                  │  │
│  │                                         │                  │  │
│  │  [Google Drive 15GB] [MEGA 20GB] [OneDrive 5GB] [pCloud]  │  │
│  │  [Filen 10GB] [Box 10GB] [Icedrive 10GB] [Koofr 10GB]...  │  │
│  │                                                            │  │
│  │  Content: encrypted blocks ONLY (AES-256-GCM ciphertext)  │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Data Flow: Viewing a Photo

```
1. App loads timeline
   → GET api.dudenest.com/api/v1/files/timeline
   → Backend returns: [{file_id, name, date, thumbnail_id, ...}]

2. App requests thumbnails
   → GET relay.local/thumbnails/{thumbnail_id}  (via WireGuard)
   → Relay: serve from local SQLite cache
   → App: renders gallery grid INSTANTLY

3. User taps a photo
   → GET relay.local/files/{file_id}  (via WireGuard)
   → Relay: lookup Block Map → find blocks on cloud accounts
   → Relay: parallel download from 6 accounts (data shards)
   → Relay: AES-256-GCM decrypt each block
   → Relay: Reed-Solomon reconstruct original file
   → Relay: stream to App via WireGuard
   → Time: ~1-3 seconds
```

## Data Flow: Uploading a Photo

```
1. App sends file to Relay
   → POST relay.local/upload  (via WireGuard)
   → Payload: raw file bytes

2. Relay processes file
   → Split into 8 MB chunks (e.g., 24 MB photo → 3 chunks)
   → Reed-Solomon 6+3 → 9 encoded shards (6 data + 3 parity)
   → Each shard encrypted: AES-256-GCM, key = HKDF(master_key, shard_id)
   → Parallel upload to 9 cloud accounts

3. Relay generates thumbnail
   → Resize to 256x256 (libvips)
   → Store in local SQLite thumbnail cache

4. Relay updates Block Map
   → SQLite: {file_id → [{shard_id, account, path}]}

5. Relay reports to Backend
   → POST api.dudenest.com/api/v1/files
   → Payload: metadata ONLY (name, date, GPS, size, thumbnail_ref)
   → Backend stores metadata in PostgreSQL
```

## Zero-Knowledge Guarantee

The Dudenest backend and cloud providers never have access to:

| Data | Where It Is | Who Can Access |
|------|-------------|----------------|
| File content | Cloud accounts (encrypted) | User only (via Relay) |
| Encryption keys | Relay only | User only |
| Block Map | Relay only | User only |
| Cloud tokens | Relay only | User only |
| Thumbnails | Relay (local cache) | User only |
| File metadata | Dudenest Backend | User + Dudenest |

## Component Repositories

| Repo | Language | Visibility | Purpose |
|------|----------|-----------|---------|
| [dudenest](https://github.com/dudenest/dudenest) | Flutter/Dart | Public | Client app |
| [dudenest-relay](https://github.com/dudenest/dudenest-relay) | Go | Public | Relay daemon |
| [dudenest-backend](https://github.com/dudenest/dudenest-backend) | Go | Public | SaaS API |
| dudenest-infra | Ansible/YAML | Private | NETOL infra |

## Landing Page

The project landing page (original Dudenest brand site):
- **Repo**: https://gitlab.com/dudenest/dudenest.com
- **Live**: https://dudenest.netol.io (via NETOL HAProxy + GitLab Pages)
- **Stack**: HTML5 + Tailwind CSS + Vanilla JS (static site)
- **CI/CD**: GitLab Pipeline → GitLab Pages → HAProxy SSL

The landing page was created in January 2026 and establishes the Dudenest brand:
- Tagline: "Beyond the horizon, inside the nest"
- Theme: eco-friendly infinite cloud storage, bird nest metaphor
- Mascot concept: "The Dude" — tech-hermit bird with sunglasses

---

**Author**: Dariusz Porczyński
