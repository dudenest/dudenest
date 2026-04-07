# Relay HTTP API

**Author**: Dariusz Porczyński
**Last Updated**: 2026-04-06
**Base URL (dev)**: `http://localhost:8086` (SSH tunnel: `ssh -f -N -L 8086:192.168.0.119:8086 root@10.51.1.101`)
**Base URL (prod)**: `http://10.71.0.1:8086` (Headscale WireGuard)

---

## Authentication

None — API is accessible only through WireGuard (Headscale). The network perimeter is the security boundary.

---

## CORS

All endpoints return:
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

---

## Endpoints

### GET /health
Check if the relay is running.
```
200 OK
ok
```

---

### GET /providers
List of authenticated cloud accounts with quota.

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
List all uploaded files (FileMaps).

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
Upload a file via multipart/form-data.

**Request:** `Content-Type: multipart/form-data`, field `file`

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
Download a file — returns raw bytes.

**Response 200:** `Content-Type: application/octet-stream`

**Curl example:**
```bash
curl http://localhost:8086/files/abc123def456 -o photo.jpg
```

---

### DELETE /files/{file_id}
Delete a file from all cloud shards.

**Response 200:**
```json
{"status": "deleted", "file_id": "abc123def456..."}
```

---

### GET /auth/status
OAuth session status (browser auth API).

### POST /auth/start
Start an OAuth session in Chromium (VNC display :99).

### GET /auth/sessions
List active auth sessions.

---

## Errors

All errors return JSON:
```json
{"error": "error description"}
```

| Code | Meaning |
|------|---------|
| 400 | Missing `file` field or parse error |
| 404 | File not found |
| 500 | Internal relay error (upload/download/erasure) |
| 503 | Provider unavailable |

---

## Performance (benchmark 2026-04-06, relay-poc VM)

| Operation | Result | Backend |
|-----------|--------|---------|
| Upload 4MB | 0.9 MB/s | GDrive (9 shards parallel) |
| Download 4MB | 3.2 MB/s | GDrive (6 shards + RS decode) |
| Upload baseline (local) | 19.8 MB/s | filesystem |

Bottleneck: GDrive API (3 round-trips/shard), not the relay code.
