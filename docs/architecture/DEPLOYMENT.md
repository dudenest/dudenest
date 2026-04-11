# Deployment — Flutter Web on NETOL Docker Swarm

**Author**: Dariusz Porczyński
**Last Updated**: 2026-04-07
**Status**: ✅ LIVE — pipeline active, app running on Swarm

---

## Deployment Architecture

```
push → github.com/dudenest/dudenest (main)
         │
         ▼
    GitHub Actions
    ┌─────────────────────────────────────────────┐
    │ Job: build (ubuntu-latest, github-hosted)    │
    │  1. subosito/flutter-action — flutter stable │
    │  2. flutter pub get                          │
    │  3. flutter build web --release              │
    │  4. docker build (Dockerfile + build/web/)   │
    │  5. push → ghcr.io/dudenest/dudenest:sha    │
    └─────────────────────────────────────────────┘
         │
         ▼
    ┌─────────────────────────────────────────────┐
    │ Job: deploy (self-hosted, label: netol-swarm)│
    │  Runner: node006.netol.io (Docker Swarm mgr) │
    │  1. docker login ghcr.io ($GITHUB_TOKEN)     │
    │  2. docker stack deploy dudenest-web         │
    │     --with-registry-auth (forwarded to nodes)│
    │  3. docker service ps dudenest-web_web       │
    │  4. Purge Cloudflare cache (CF_API_TOKEN)    │
    └─────────────────────────────────────────────┘
         │
         ▼
    Docker Swarm (node001-007 + sydney + canada)
    Service: dudenest-web_web
    Image: ghcr.io/dudenest/dudenest:sha
    Network: PROXY_NETOL_PROD
    Replicas: 2 (max 1 per node)
         │
         ▼
    Traefik → app.dudenest.com (HAProxy ns2 → SSL)
```

---

## Components

### Dockerfile (`/Dockerfile`)
Single-stage build — copies pre-built Flutter web into nginx:
```dockerfile
FROM nginx:alpine
COPY build/web /usr/share/nginx/html      # pre-built by CI
COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
```

### nginx.conf (`/docker/web/nginx.conf`)
SPA routing — all paths fall back to `index.html`. Non-hashed files (main.dart.js, index.html) served with `no-store` to bypass CDN cache:
```nginx
location ~* ^/(index\.html|main\.dart\.js|...)$ {
    add_header Cache-Control "no-store, no-cache, must-revalidate";
    add_header Cloudflare-CDN-Cache-Control "no-store";
}
location / { try_files $uri $uri/ /index.html; }
```

### docker-stack.yml (`/docker/web/docker-stack.yml`)
```yaml
services:
  web:
    image: ghcr.io/dudenest/dudenest:${IMAGE_TAG}
    networks: [PROXY_NETOL_PROD]
    deploy:
      replicas: 2
      labels:
        - traefik.http.routers.dudenest-web.rule=Host(`app.dudenest.com`)
```

---

## Infrastructure

### GitHub Actions Runner
- **Image**: `myoung34/github-runner:latest`
- **Scope**: org `dudenest` (all repos)
- **Label**: `netol-swarm`
- **Location**: Docker Swarm service `github-runner_runner`
- **Current node**: node006.netol.io
- **Stack**: `/.data/github-runner/` (node001)

### GHCR (GitHub Container Registry)
- **Image**: `ghcr.io/dudenest/dudenest`
- **Tags**: `latest` + `<git-sha>` on every push
- **Auth**: `GITHUB_TOKEN` (built-in, automatic)

### Cloudflare CDN
- **Domain**: `app.dudenest.com` (proxied, orange cloud)
- **Cache**: `Cloudflare-CDN-Cache-Control: no-store` for non-hashed JS files
- **Post-deploy purge**: automated via `CF_API_TOKEN` + `CF_ZONE_ID` secrets
- **Browser Cache TTL**: set to "Respect Existing Headers" in Cloudflare dashboard

### HAProxy (ns2, 206.189.31.117)
- **Domain**: `app.dudenest.com`
- **Routing**: HAProxy SNI → localhost:12443 → HTTP frontend → Traefik → dudenest-web_web:80

### Cloudflare DNS
- `A app.dudenest.com → 206.189.31.117`

---

## Relay Deployment (Go)

The Dudenest Relay is deployed to the `relay-poc` VM (reference implementation) using a specialized GitHub Actions workflow.

### Continuous Deployment (CD)
1. **Build**: Go binaries are built for multiple platforms (amd64, arm64, windows, etc.).
2. **Deployer Container (DooD)**: Since the self-hosted runner is isolated from ZeroTier, it uses **Docker-out-of-Docker**:
   - Creates a unique temporary container (`alpine`) with `--network host`.
   - Copies the binary and SSH keys into the container via `docker cp`.
   - Executes deployment commands from within the container to access the host's ZeroTier interfaces.
3. **SSH ProxyJump**: Connection to `relay-poc` (192.168.0.119) is established via a jump host `pve101` (10.51.1.101).
4. **Service Restart**: The `relay.service` is restarted on the target VM.

---

## Diagnostics

```bash
# Swarm service state
ssh root@node001.netol.io \
  "docker service ps dudenest-web_web --no-trunc"

# Service logs
ssh root@node001.netol.io \
  "docker service logs dudenest-web_web --tail 50"

# GitHub runner status
curl -s -H "Authorization: token <PAT>" \
  https://api.github.com/orgs/dudenest/actions/runners | jq '.runners[].status'

# Verify Cloudflare is bypassed
curl -sI https://app.dudenest.com/main.dart.js | grep -E "cf-cache-status|cache-control|age"
```

---

## Local Development

```bash
# Requirements: Flutter 3.41.6 (brew install flutter), SSH tunnel to relay-poc
ssh -f -N -L 8086:192.168.0.119:8086 root@10.51.1.101

# Run
cd ~/Architect/github.com/dudenest/dudenest
flutter run -d chrome --web-port 8787
# App: http://localhost:8787
```
