# Relay HTTP API

**Author**: Dariusz Porczyński
**Last Updated**: 2026-04-06
**Base URL (dev)**: `http://localhost:8086` (SSH tunnel: `ssh -f -N -L 8086:192.168.0.119:8086 root@10.51.1.101`)
**Base URL (prod)**: `http://10.71.0.1:8086` (Headscale WireGuard)

---

## Authentication

Brak — API dostępne tylko przez WireGuard (Headscale). Sieć = granica bezpieczeństwa.

---

## CORS

Wszystkie endpointy zwracają:
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

---

## Endpointy

### GET /health
Sprawdzenie czy relay działa.
```
200 OK
ok
```

---

### GET /providers
Lista zalogowanych kont chmurowych z quotą.

**Response 200:**
```json
{
  "providers": [
    {
      "id": "gdrive_gdrive_1775142563479",
      "email": "user@gmail.com",
      "quota_total_gb": 15.1,
      "quota_used_gb": 0.022,
      "available": true
    }
  ]
}
```

---

### GET /files
Lista wszystkich przesłanych plików (FileMaps).

**Response 200:**
```json
{
  "files": [
    {
      "file_id": "abc123def456...",
      "name": "photo.jpg",
      "size": 2097152,
      "hash": "sha256:deadbeef...",
      "created": "2026-04-06T12:00:00Z"
    }
  ]
}
```

---

### POST /files/upload
Upload pliku przez multipart/form-data.

**Request:** `Content-Type: multipart/form-data`, pole `file`

**Response 200:**
```json
{
  "file_id": "abc123def456...",
  "name": "photo.jpg",
  "size": 2097152,
  "hash": "sha256:deadbeef...",
  "chunks": 9
}
```

**Curl example:**
```bash
curl -X POST http://localhost:8086/files/upload \
  -F "file=@/path/to/photo.jpg"
```

---

### GET /files/{file_id}
Download pliku — zwraca surowe bajty.

**Response 200:** `Content-Type: application/octet-stream`

**Curl example:**
```bash
curl http://localhost:8086/files/abc123def456 -o photo.jpg
```

---

### DELETE /files/{file_id}
Usuwa plik ze wszystkich shardów w chmurze.

**Response 200:**
```json
{"status": "deleted", "file_id": "abc123def456..."}
```

---

### GET /auth/status
Status sesji OAuth (browser auth API).

### POST /auth/start
Uruchamia sesję OAuth w Chromium (VNC display :99).

### GET /auth/sessions
Lista aktywnych sesji auth.

---

## Błędy

Wszystkie błędy zwracają JSON:
```json
{"error": "opis błędu"}
```

| Kod | Znaczenie |
|-----|-----------|
| 400 | Brak pola `file` lub błąd parsowania |
| 404 | Plik nie istnieje |
| 500 | Błąd wewnętrzny relay (upload/download/erasure) |
| 503 | Provider niedostępny |

---

## Wydajność (benchmark 2026-04-06, relay-poc VM)

| Operacja | Wynik | Backend |
|----------|-------|---------|
| Upload 4MB | 0.9 MB/s | GDrive (9 shardów równolegle) |
| Download 4MB | 3.2 MB/s | GDrive (6 shardów + RS decode) |
| Upload baseline (local) | 19.8 MB/s | filesystem |

Bottleneck: GDrive API (3 round-tripy/shard), nie kod relay.
