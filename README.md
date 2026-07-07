# BadSector

**Self-Hosted Edge Security Platform**

Every incoming HTTP request enters BadSector first. BadSector decides whether the request should continue to the backend, be challenged, delayed, rate limited, cached, redirected, blocked, or receive a custom response — before expensive processing occurs.

> BadSector is not a reverse proxy manager. It is not a traditional WAF. It is a policy-driven edge security platform that runs inside your infrastructure.

## Architecture Overview

```
                    ┌─────────────────────────────────────────┐
                    │              HAProxy                     │
                    │  TLS · HTTP/2 · HTTP/3 · Stick Tables   │
                    │  Connection Limits · L4 Optimizations   │
                    └──────────────────┬──────────────────────┘
                                       │
                    ┌──────────────────▼──────────────────────┐
                    │           OpenResty (Engine)             │
                    │  Configurable Module Pipeline · Policies │
                    │  Lua Plugins · Hot Reload · Tracing      │
                    └──────────────────┬──────────────────────┘
                                       │
                              Backend / Origin
```

| Component | Role |
|-----------|------|
| **badsector-engine** | Core runtime inside OpenResty. Executes the request pipeline. |
| **badsector-api** | REST API for configuration, sites, policies, and runtime state. |
| **badsector-ui** | Dashboard — sites, rate limits, policies, pipeline, live tracing. |
| **badsector-worker** | Background jobs: GeoIP, threat intel, certificate renewal. |
| **badsector-agent** | Optional per-node agent for distributed deployments. |
| **badsector-cli** | Command-line management tool. |

## Request Pipeline

Modules are independent, reorderable, and configurable per site:

```
Request → Access Lists → Trusted Bots → GeoIP → ASN → Policies
       → Rate Limit → Challenge → Managed WAF → Cache → Reverse Proxy → Backend
```

Each module receives a `RequestContext` and returns a terminal or non-terminal decision. Execution stops immediately on terminal decisions.

## Development Status

| Area | Status | Docs |
|------|--------|------|
| Engine core (pipeline, RequestContext) | Done | [ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Modules: access_lists, geoip, policies, reverse_proxy | Done | [MODULES.md](docs/MODULES.md) |
| Module: rate_limiter (Redis + shared dict) | Done | [RATE_LIMITER.md](docs/RATE_LIMITER.md) |
| API: sites CRUD + default pipeline | Done | [API.md](docs/API.md) |
| API: rate limit config | Done | [API.md](docs/API.md) |
| UI: Sites management (+ upstream URL, pipeline summary) | Done | [UI.md](docs/UI.md) |
| UI: Rate limit management | Done | [UI.md](docs/UI.md) |
| UI: Policies CRUD | Done | [UI.md](docs/UI.md) |
| UI: Pipeline drag-and-drop | Done | [UI.md](docs/UI.md) |
| Module: managed_waf (Coraza) | Done | [MANAGED_WAF.md](docs/MANAGED_WAF.md) |
| Module: trusted_bots, ip_reputation | Done | [MODULES.md](docs/MODULES.md) |
| Live request trace + explainability UI | Done | [TRACE.md](docs/TRACE.md) |
| API JWT auth + engine hot reload | Done | [API.md](docs/API.md) |
| Docker test environment + smoke test | Done | [TEST_ENV.md](docs/TEST_ENV.md) |
| CI (Go test + Docker smoke) | Done | `.github/workflows/ci.yml` |
| Dashboard live metrics | Done | [API.md](docs/API.md) |
| HAProxy in dev compose | Done | [TEST_ENV.md](docs/TEST_ENV.md) |
| All pipeline modules (stubs where noted) | Done | [MODULES.md](docs/MODULES.md) |
| Edge security modules UI + API | Done | [SECURITY_MODULES.md](docs/SECURITY_MODULES.md) |
| GeoIP + ASN (MaxMind MMDB, worker sync) | Done | [GEOIP.md](docs/GEOIP.md) |
| Custom Rules + TLS (Let's Encrypt) | Done | [SECURITY_MODULES.md](docs/SECURITY_MODULES.md), [CERTIFICATES.md](docs/CERTIFICATES.md) |

See [CHANGELOG.md](CHANGELOG.md) for release notes.

## GitHub & Sunucu Kurulumu

```bash
# GitHub'a ilk push (Git Bash)
git init && git add . && git commit -m "Initial commit"
git remote add origin https://github.com/KULLANICI_ADINIZ/BadSector.git
git push -u origin main

# Sunucuda kurulum
sudo git clone https://github.com/KULLANICI_ADINIZ/BadSector.git /opt/badsector
cd /opt/badsector && cp .env.example .env && nano .env
sudo ./scripts/install-server.sh /opt/badsector
```

Detaylı rehber: [docs/DEPLOY.md](docs/DEPLOY.md)

**Güncelleme:** değişiklikler repoya push edilir; sunucuda `bash scripts/update-server.sh` (elle patch yok).

## Quick Start

**Test environment (Docker — Linux/macOS/WSL2):**

```bash
./scripts/setup-dev-data.sh
docker compose up -d --build
./scripts/smoke-test.sh
```

See [docs/TEST_ENV.md](docs/TEST_ENV.md) for full test setup, manual checks, and troubleshooting.

```bash
# Or run locally (API + UI only; engine needs Docker)
make dev-api   # :8080
make dev-ui    # :3000
```

| Service | URL |
|---------|-----|
| Dashboard | http://localhost:3000 |
| API health | http://localhost:8080/health |
| Engine | http://localhost:9080 |

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, data flow, performance budget |
| [MODULES.md](docs/MODULES.md) | Module interface and built-in modules |
| [RATE_LIMITER.md](docs/RATE_LIMITER.md) | Rate limiter module config and Redis setup |
| [MANAGED_WAF.md](docs/MANAGED_WAF.md) | Coraza WAF module config and production setup |
| [POLICIES.md](docs/POLICIES.md) | Policy engine schema and compilation |
| [API.md](docs/API.md) | REST API reference |
| [UI.md](docs/UI.md) | Dashboard pages and workflows |
| [DECISIONS.md](docs/DECISIONS.md) | Architecture decision records |
| [SECURITY_MODULES.md](docs/SECURITY_MODULES.md) | Edge security module config (GeoIP, ASN, headers, burst, challenges) |
| [GEOIP.md](docs/GEOIP.md) | MaxMind GeoLite2 setup, worker sync, module config |
| [CERTIFICATES.md](docs/CERTIFICATES.md) | Let's Encrypt TLS setup and renewal |
| [DEPLOY.md](docs/DEPLOY.md) | GitHub push and Linux server install |

## Performance Targets

- **< 1ms** internal module execution (hot path)
- **100k+** concurrent connections
- Minimal memory allocations per request
- Redis for counters · SQLite (dev) · PostgreSQL (prod)
- Configuration hot reload — no nginx reload for policy changes

## License

Apache License 2.0 — see [LICENSE](LICENSE).
