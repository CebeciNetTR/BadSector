# Test Environment

BadSector’s first test environment runs entirely in **Docker Compose** (Linux/macOS/WSL2). Windows native is not supported for the engine; use WSL2 or a Linux VM.

## Quick start

```bash
./scripts/setup-dev-data.sh
docker compose up -d --build
./scripts/smoke-test.sh
```

| Service | URL | Role |
|---------|-----|------|
| Dashboard | http://localhost:3000 | React UI + live metrics |
| API | http://localhost:8080 | Config, sites, traces, metrics |
| HAProxy → Engine | http://localhost:9080 | L7 edge entry (use `Host: localhost`) |
| Backend | http://localhost:8081 | Example nginx origin |

## Smoke test

`scripts/smoke-test.sh` verifies:

1. API `/health`
2. Engine `/badsector/health`
3. UI responds
4. `GET /api/v1/sites`
5. Engine proxies to backend (`Host: localhost`)
6. UI nginx proxies `/api/v1/sites`

Override URLs:

```bash
BADSECTOR_API_URL=http://localhost:8080 \
BADSECTOR_ENGINE_URL=http://localhost:9080 \
BADSECTOR_UI_URL=http://localhost:3000 \
./scripts/smoke-test.sh
```

## Manual checks

```bash
# API
curl -s http://localhost:8080/health
curl -s http://localhost:8080/api/v1/sites

# Engine → backend
curl -s -H "Host: localhost" http://localhost:9080/

# Generate trace (live_trace enabled on default site)
curl -s -H "Host: localhost" http://localhost:9080/test
curl -s http://localhost:8080/api/v1/sites/<site-id>/traces | head
```

## Docker-specific defaults

| Setting | Compose value |
|---------|---------------|
| `BADSECTOR_DEFAULT_BACKEND_URL` | `http://backend:80` |
| `BADSECTOR_AUTH_DISABLED` | `true` (dev) |
| `BADSECTOR_ENGINE_RELOAD_URL` | `http://engine:8080/badsector/admin/reload` |
| UI `VITE_API_URL` | `/api/v1` (build arg; nginx proxies to API) |

Engine nginx uses Docker DNS resolver `127.0.0.11` for dynamic `proxy_pass` hostnames.

## Startup order

1. Postgres + Redis (healthchecks)
2. API (writes `sites.json`, healthcheck)
3. Engine (waits for config, mounts GeoIP + Coraza rules)
4. HAProxy (public edge on `:9080`)
5. UI + worker

## Optional: GeoIP database

```bash
export MAXMIND_LICENSE_KEY=your_key
./scripts/download-geoip.sh
docker compose restart engine
```

Without MMDB, the `geoip` module falls back to `CF-IPCountry` / `X-Country-Code` headers.

## Mounted volumes (engine)

| Host path | Container | Purpose |
|-----------|-----------|---------|
| `./data/geoip` | `/etc/badsector/geoip` | GeoLite2-Country.mmdb |
| `./engine/coraza/rules` | `/etc/badsector/coraza/rules` | CRS-style dev rules |
| `runtime_config` volume | `/etc/badsector/runtime` | Generated `sites.json` |

## CI

GitHub Actions (`.github/workflows/ci.yml`):

- `go test ./...`
- `docker compose up --build` + smoke test

## Local dev (without full stack)

```bash
# API only (SQLite + local Redis)
export BADSECTOR_AUTH_DISABLED=true
make dev-api

# UI with Vite proxy
make dev-ui
```

Engine requires Docker for realistic L7 testing.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Engine 404 “Site not configured” | Wait for API health; check `docker compose logs api` |
| Proxy 502 | Verify `backend_url` is `http://backend:80` in runtime config |
| UI API 404 | Rebuild UI image (`VITE_API_URL=/api/v1` + nginx proxy) |
| Empty traces | Ensure `live_trace: true` in site settings; send traffic via engine |

## Not in dev compose

- HAProxy (L4) — see `deploy/haproxy/`
- GeoIP MMDB — mount volume if enabling `geoip` module
- Coraza CRS rules — builtin fallback used; mount rules for production
