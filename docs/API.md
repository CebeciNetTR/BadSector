# REST API Reference

Base URL: `http://localhost:8080/api/v1`

All responses are JSON. Errors return `{ "message": "..." }`.

When authentication is enabled (default), send `Authorization: Bearer <token>` on all routes except login. Set `BADSECTOR_AUTH_DISABLED=true` for local development.

## Health

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | API health check (outside `/api/v1`) |

## Authentication

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/login` | Exchange username/password for JWT (no auth required) |

### Login body

```json
{
  "username": "admin",
  "password": "badsector"
}
```

### Response

```json
{
  "token": "<jwt>",
  "expires_at": "2026-07-08T00:00:00Z",
  "role": "admin"
}
```

Credentials: `BADSECTOR_ADMIN_USER`, `BADSECTOR_ADMIN_PASSWORD`. Token signing: `BADSECTOR_JWT_SECRET`.

## Sites

| Method | Path | Description |
|--------|------|-------------|
| GET | `/sites` | List all sites |
| POST | `/sites` | Create site (+ default pipeline) |
| GET | `/sites/:id` | Get site with pipeline and policies |
| PUT | `/sites/:id` | Update site |
| DELETE | `/sites/:id` | Delete site, pipeline, and policies |

### Create / Update body

```json
{
  "name": "Production API",
  "hosts": ["api.example.com", "www.example.com"],
  "enabled": true,
  "backend_url": "http://127.0.0.1:8081",
  "settings": {
    "live_trace": true,
    "debug_trace": false
  }
}
```

| Setting | Description |
|---------|-------------|
| `live_trace` | Buffer request traces in Redis for dashboard |
| `debug_trace` | Add `X-BadSector-Trace` header on responses |

`backend_url` updates the `reverse_proxy` pipeline stage. Normalized to `scheme://host` (default `http://127.0.0.1:8081`).

Validation:
- `name` is required
- At least one hostname required
- Hostnames are normalized (trimmed, lowercased, deduplicated)

On create, a default pipeline is assigned automatically:

```
access_lists → trusted_bots → ip_reputation → policies → rate_limiter → managed_waf → reverse_proxy
```

## Metrics

| Method | Path | Description |
|--------|------|-------------|
| GET | `/metrics/dashboard` | Aggregated request counters from Redis |

### Response

```json
{
  "requests_total": 120,
  "blocked": 3,
  "challenged": 0,
  "rate_limited": 1,
  "allowed": 116,
  "active_sites": 1,
  "decisions": { "ALLOW": 116, "BLOCK": 3, "RATE_LIMIT": 1 },
  "edge": { "api": "ok", "engine": "unknown", "redis": "ok" }
}
```

## Request Traces

| Method | Path | Description |
|--------|------|-------------|
| GET | `/sites/:id/traces?limit=50` | Recent live traces (newest first) |

See [TRACE.md](TRACE.md).

## Rate Limits

| Method | Path | Description |
|--------|------|-------------|
| GET | `/sites/:id/rate-limits` | Get rate limiter module config |
| PUT | `/sites/:id/rate-limits` | Save config and regenerate runtime |

### Response / Request body

```json
{
  "enabled": true,
  "config": {
    "use_redis": true,
    "fail_mode": "open",
    "redis": {
      "host": "redis",
      "port": 6379,
      "timeout": 100
    },
    "rules": [
      {
        "id": "rl-global-ip",
        "name": "Global per-IP limit",
        "enabled": true,
        "key_by": "ip",
        "limit": 100,
        "burst": 20,
        "window": "1m",
        "paths": ["/*"]
      }
    ]
  }
}
```

If no `rate_limiter` pipeline stage exists, PUT creates one before `reverse_proxy`.

See [RATE_LIMITER.md](RATE_LIMITER.md) for rule fields and engine behavior.

| GET | `/geoip/status` | MaxMind MMDB availability |

## Edge Security Modules

| Method | Path | Module |
|--------|------|--------|
| GET/PUT | `/sites/:id/geoip` | GeoIP module config |
| GET/PUT | `/sites/:id/asn` | ASN filter |
| GET/PUT | `/sites/:id/header-validation` | Header validation |
| GET/PUT | `/sites/:id/burst-detection` | Burst detection |
| GET/PUT | `/sites/:id/js-challenge` | JS challenge |
| GET/PUT | `/sites/:id/cookie-challenge` | Cookie challenge |
| GET/PUT | `/sites/:id/custom-rules` | Custom rules (expression DSL) |

### Certificates

| Method | Path | Description |
|--------|------|-------------|
| GET | `/certificates` | List all (`?site_id=`) |
| GET | `/sites/:id/certificates` | List for site |
| POST | `/sites/:id/certificates` | Create / issue `{domain, email?, issue?}` |
| POST | `/certificates/:certId/issue` | Obtain from Let's Encrypt |
| POST | `/certificates/:certId/renew` | Renew certificate |
| DELETE | `/certificates/:certId` | Delete certificate |

See [SECURITY_MODULES.md](SECURITY_MODULES.md).

## Managed WAF (Coraza)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/sites/:id/managed-waf` | Get managed_waf module config |
| PUT | `/sites/:id/managed-waf` | Save config and regenerate runtime |

See [MANAGED_WAF.md](MANAGED_WAF.md) for configuration reference.

## Policies

| Method | Path | Description |
|--------|------|-------------|
| GET | `/sites/:id/policies` | List policies (priority order) |
| POST | `/sites/:id/policies` | Create policy |
| PUT | `/sites/:id/policies/:policyId` | Update policy |
| DELETE | `/sites/:id/policies/:policyId` | Delete policy |

### Policy body

```json
{
  "name": "Block admin non-EU",
  "priority": 100,
  "enabled": true,
  "conditions": {
    "operator": "and",
    "rules": [
      { "type": "path", "operator": "prefix", "value": "/admin" },
      { "type": "country", "operator": "not_in", "value": ["DE", "FR"] }
    ]
  },
  "actions": [
    { "type": "return_444" },
    { "type": "log", "level": "warn", "message": "Admin geo block" }
  ]
}
```

See [POLICIES.md](POLICIES.md) for condition and action schema.

## Pipeline

| Method | Path | Description |
|--------|------|-------------|
| GET | `/sites/:id/pipeline` | List pipeline stages (ordered) |
| PUT | `/sites/:id/pipeline` | Replace pipeline order and enabled state |

### PUT body

Array of stages (config preserved from existing stages when omitted):

```json
[
  { "module": "access_lists", "enabled": true, "config": "{\"deny\":[],\"allow\":[]}" },
  { "module": "policies", "enabled": true, "config": "" },
  { "module": "rate_limiter", "enabled": true, "config": "" },
  { "module": "reverse_proxy", "enabled": true, "config": "" }
]
```

Rules:
- `reverse_proxy` must be the last module when present
- Empty `config` merges from existing DB config or module defaults
- Policies module config is compiled from DB at runtime regardless

## Runtime

| Method | Path | Description |
|--------|------|-------------|
| POST | `/runtime/reload` | Regenerate `sites.json` and signal engine hot reload |

Called automatically after most write operations. The UI also calls this explicitly after save.

Engine reload target: `BADSECTOR_ENGINE_RELOAD_URL` (default `http://engine:8080/badsector/admin/reload`) with `BADSECTOR_ENGINE_ADMIN_TOKEN`.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BADSECTOR_API_ADDR` | `:8080` | API listen address |
| `BADSECTOR_DATABASE_URL` | `sqlite://./data/badsector.db` | PostgreSQL or SQLite |
| `BADSECTOR_RUNTIME` | `./runtime` | Generated config output path |
| `BADSECTOR_REDIS_URL` | `redis://localhost:6379` | Redis (traces + rate limits) |
| `BADSECTOR_JWT_SECRET` | (dev default) | JWT signing secret |
| `BADSECTOR_AUTH_DISABLED` | `false` | Skip JWT middleware when `true` |
| `BADSECTOR_ADMIN_USER` | `admin` | Login username |
| `BADSECTOR_ADMIN_PASSWORD` | `badsector` | Login password |
| `BADSECTOR_ENGINE_RELOAD_URL` | `http://engine:8080/badsector/admin/reload` | Engine hot reload endpoint |
| `BADSECTOR_ENGINE_ADMIN_TOKEN` | `badsector-engine-token` | Bearer token for engine admin |

## Database Seed

On first startup with an empty database, the API creates a **Default Site** with hostnames `localhost` and `127.0.0.1` and a default pipeline.
