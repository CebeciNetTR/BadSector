# Changelog

All notable changes to BadSector are documented here.

## [Unreleased]

### Added

- **Edge security modules UI + API** — ASN, header validation, burst detection, JS/cookie challenge ([SECURITY_MODULES.md](docs/SECURITY_MODULES.md))
- **Dashboard metrics** — Engine Redis counters, `GET /metrics/dashboard`, live UI
- **HAProxy dev edge** — `:9080` entry point in docker compose
- **GeoIP + ASN (MaxMind)** — Country/ASN MMDB lookup in engine, worker auto-sync, `GET /geoip/status`, Edge Security UI ([GEOIP.md](docs/GEOIP.md))
- **Custom Rules module** — Safe expression DSL in pipeline, Edge Security UI ([SECURITY_MODULES.md](docs/SECURITY_MODULES.md))
- **TLS / Let's Encrypt** — ACME HTTP-01, certificate API + UI, worker auto-renew ([CERTIFICATES.md](docs/CERTIFICATES.md))
- **GeoIP volume** — `./data/geoip` mount + download script
- **Coraza CRS dev rules** — `./engine/coraza/rules` mount + file rule loader
- **Remaining modules** — cache, asn, header_validation, burst_detection, threat_intel, js/cookie challenge
- **Docker test environment** — Compose healthchecks, engine config wait, smoke test script, CI workflow
- **Live request trace** — Redis trace buffer, `GET /sites/:id/traces`, dashboard polling UI ([TRACE.md](docs/TRACE.md))
- **Modules: trusted_bots, ip_reputation** — Early pipeline filters before policies/WAF
- **API JWT auth** — `POST /auth/login`, Bearer middleware, env-configurable
- **Engine hot reload** — `POST /badsector/admin/reload`, API signals engine after config generate
- **Engine: dynamic backend URL** — `reverse_proxy` module sets `$badsector_backend` per request
- **API: backend_url on sites** — Create/update site with upstream URL (`backend_url` field)
- **API: policy update/delete** — `PUT/DELETE /api/v1/sites/:id/policies/:policyId`
- **UI: Sites upstream field** — Edit reverse_proxy backend URL from site form
- **UI: Pipeline summary** — Active module list on Sites page
- **UI: Policies page** — Full CRUD with condition/action builder
- **Engine: managed_waf module** — Coraza WAF pipeline module with builtin fallback rules
- **API: managed-waf endpoints** — `GET/PUT /api/v1/sites/:id/managed-waf`
- **UI: Managed WAF page** — Coraza config (mode, paranoia, exclude paths)
- **UI: Pipeline drag-and-drop** — Reorder modules, enable/disable, add/remove, save & reload
- **API: pipeline update** — Preserves module config, validates reverse_proxy last
- **Engine: rate_limiter module** — Redis-backed fixed-window rate limiting with shared dict fallback, burst support, and policy integration (`ctx.enrich.rate`)
- **Engine: redis client** — Connection pooling, atomic INCR+EXPIRE Lua script
- **API: rate limit endpoints** — `GET/PUT /api/v1/sites/:id/rate-limits`
- **API: sites improvements** — Validation, default pipeline on create, cascade delete
- **API: default site seed** — Creates demo site when database is empty
- **UI: Rate Limits page** — Site selector, module settings, rule CRUD, save & reload
- **UI: Sites page** — Site CRUD, hostname editor, debug trace toggle, delete confirmation
- **Schemas** — `schemas/rate_limiter.json`, `schemas/policy.json`
- **Docs** — `docs/RATE_LIMITER.md`, `docs/API.md`, `docs/UI.md`

### Changed

- Docker default upstream: `http://backend:80` via `BADSECTOR_DEFAULT_BACKEND_URL`
- Engine nginx: Docker DNS resolver for dynamic `proxy_pass`
- UI Docker image: `/api` nginx proxy + `VITE_API_URL=/api/v1` at build time
- Pipeline UI: only implemented engine modules can be added
- `docker-compose.yml` — API/engine healthchecks, startup ordering
- Site creation default pipeline includes trusted_bots and ip_reputation
- API config changes trigger engine hot reload via `BADSECTOR_ENGINE_RELOAD_URL`

## [0.1.0] — 2026-07-07

### Added

- Initial project scaffold
- Engine core: pipeline executor, RequestContext, decision types
- Built-in modules: access_lists, geoip, policies, reverse_proxy
- Go API skeleton with sites, policies, pipeline endpoints
- React dashboard skeleton
- Docker Compose, HAProxy config, Helm chart skeleton
- Architecture documentation
