# Deployment — Flutter Web na NETOL Docker Swarm

**Author**: Dariusz Porczyński
**Last Updated**: 2026-04-06
**Status**: ✅ DZIAŁA — pipeline aktywny, app w Swarmie

---

## Architektura Deploymentu

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
    │     --with-registry-auth (fwd do workerów)   │
    │  3. docker service ps dudenest-web_web       │
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

## Komponenty

### Dockerfile (`/Dockerfile`)
Dwuetapowy build — Flutter web + nginx:
```dockerfile
FROM nginx:alpine
COPY build/web /usr/share/nginx/html      # pre-built przez CI
COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
```

### nginx.conf (`/docker/web/nginx.conf`)
SPA routing — wszystkie ścieżki → `index.html`:
```nginx
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

## Infrastruktura

### GitHub Actions Runner
- **Image**: `myoung34/github-runner:latest`
- **Scope**: org `dudenest` (wszystkie repo)
- **Label**: `netol-swarm`
- **Lokalizacja**: Docker Swarm service `github-runner_runner`
- **Aktualny node**: node006.netol.io
- **Stack**: `/.data/github-runner/` (node001)

### GHCR (GitHub Container Registry)
- **Image**: `ghcr.io/dudenest/dudenest`
- **Tags**: `latest` + `<git-sha>` przy każdym pushu
- **Auth**: `GITHUB_TOKEN` (wbudowany, automatyczny)

### HAProxy (ns2, 206.189.31.117)
- **Domain**: `app.dudenest.com`
- **Routing**: HAProxy SNI → localhost:12443 → HTTP frontend → Traefik → dudenest-web_web:80

### Cloudflare DNS
- `A app.dudenest.com → 206.189.31.117`

---

## Aktualizacja aplikacji

Każdy push do `main` → automatyczny deploy:
```bash
git push origin main
# Pipeline: ~5 min build + ~30s deploy
# Sprawdź: github.com/dudenest/dudenest/actions
```

---

## Diagnostyka

```bash
# Stan service w Swarmie
ssh -J root@10.51.1.101 root@10.51.1.221 \
  "docker service ps dudenest-web_web --no-trunc"

# Logi service
ssh -J root@10.51.1.101 root@10.51.1.221 \
  "docker service logs dudenest-web_web --tail 50"

# Status GitHub runner
curl -s -H "Authorization: token <PAT>" \
  https://api.github.com/orgs/dudenest/actions/runners | jq '.runners[].status'
```

---

## Dev (lokalne uruchamianie)

```bash
# Wymagania: Flutter 3.41.6 (brew install flutter), SSH tunnel do relay-poc
ssh -f -N -L 8086:192.168.0.119:8086 root@10.51.1.101

# Uruchomienie
cd ~/Architect/github.com/dudenest/dudenest
flutter run -d chrome --web-port 8787
# App: http://localhost:8787
```
