# BadSector Architecture

## Design Principles

1. **Performance first** — Heavy operations never run unless absolutely necessary. Target < 1ms per module on the hot path.
2. **Modularity** — Every feature is an independent module with a common interface. Enable, disable, reorder, configure per site.
3. **Event-driven context** — Modules communicate through `RequestContext`. Expensive work is done once and reused.
4. **Policy-driven** — Users configure behavior, not nginx syntax. The platform generates runtime configuration.
5. **Explainability** — Every decision is traceable. Users always know why a request was blocked.
6. **Hot reload** — Policies and module config update live without nginx reload.

## Component Topology

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ badsector-ui│────▶│ badsector-api│────▶│  PostgreSQL │
└─────────────┘     └──────┬──────┘     └─────────────┘
                           │
                    ┌──────▼──────┐     ┌─────────────┐
                    │badsector-worker│──▶│    Redis    │
                    └──────┬──────┘     └─────────────┘
                           │
                    config push / reload
                           │
┌─────────────┐     ┌──────▼──────┐     ┌─────────────┐
│   HAProxy   │────▶│badsector-engine│──▶│   Backend   │
└─────────────┘     └─────────────┘     └─────────────┘
     L4 only            L7 all
```

### HAProxy (edge)

HAProxy handles:

- TLS termination
- HTTP/2 (and optional HTTP/3 in some configs)
- Stick tables (per-IP conn / request rate)
- Connection limits (`maxconn`), thread count (`nbthread`)
- **Attack-mode edge controls** (Lua `ban_check`): Redis-backed ban silent-drop, hit accounting (batched flush to Redis), optional HTTP 429 under attack mode

HAProxy does **not** inspect request bodies or run Coraza/WAF. Full L7 policy, GeoIP, PoW, and WAF run in OpenResty.

### Flood path (summary)

```
Client → HAProxy (TLS, optional silent-drop if banned + attack mode)
      → Engine (health/acme short-circuit; ban negative-cache; pipeline)
      → Watcher (async): high hit IPs → host ipset DROP (all ports) + Redis ban
```

Engine never does a Redis round-trip on `/badsector/health` (keeps HAProxy health checks alive under load).

### OpenResty Engine (Layer 7)

All HTTP semantics and security decisions execute in OpenResty:

- Module pipeline execution
- Policy evaluation
- Rate limiting (Redis-backed counters)
- Challenges (JS, cookie, captcha)
- Managed WAF (Coraza)
- Caching
- Reverse proxy to backend

## Request Lifecycle

```
1. TCP accepted by HAProxy
2. TLS handshake (HAProxy)
3. HTTP/2 or HTTP/3 multiplexing (HAProxy)
4. Forward to OpenResty upstream
5. RequestContext created (single allocation pool)
6. Pipeline modules execute in order
7. Terminal decision → respond immediately
8. CONTINUE → next module
9. Reverse proxy module → backend (if reached)
10. Response phase modules (optional, future)
11. Trace flushed to analytics (async)
```

## Module Interface

Every module implements the same contract:

```lua
-- modules must export:
local M = {}

M.name = "geoip"
M.version = "1.0.0"
M.priority = 100  -- optional default ordering hint

-- Called once at worker init
function M.init(config) end

-- Called on config hot reload
function M.reload(config) end

-- Main handler — must be fast
function M.run(ctx) -> Decision end

return M
```

### Decision Types

| Decision | Terminal | Description |
|----------|----------|-------------|
| `ALLOW` | Yes | Allow request, skip remaining modules, proceed to backend |
| `CONTINUE` | No | Pass to next module |
| `BLOCK` | Yes | Return block response (configurable status/body) |
| `RETURN_444` | Yes | Close connection without response |
| `REDIRECT` | Yes | HTTP redirect |
| `CACHE` | Yes | Serve from cache or populate cache |
| `CHALLENGE` | Yes | Issue challenge (JS/cookie/captcha) |
| `CUSTOM_RESPONSE` | Yes | Return configured response |
| `RATE_LIMIT` | Yes | Return 429 with retry headers |
| `DELAY` | No* | Artificial delay, then continue (*configurable) |

Terminal decisions stop pipeline execution immediately.

## RequestContext

The shared event bus for a single request. Modules read and write namespaced keys.

```lua
ctx = {
  -- Immutable request data (set once)
  request = {
    id, method, uri, path, query, headers, cookies,
    body_size, scheme, host, remote_addr, remote_port,
  },

  -- Site binding
  site = { id, name, pipeline, settings },

  -- Lazy-resolved enrichments (computed once, cached on ctx)
  enrich = {
    geo = nil,      -- { country, city, lat, lon }
    asn = nil,      -- { number, org }
    bot = nil,      -- { trusted, name, score }
    fingerprint = nil,
    reputation = nil,
  },

  -- Module-scoped storage
  vars = {},        -- custom variables for policy conditions

  -- Decision trace (for dashboard)
  trace = {
    { module = "access_lists", decision = "CONTINUE", ms = 0.02, detail = "..." },
  },

  -- Terminal state (set by winning module)
  decision = nil,
  response = nil,
}
```

### Enrichment Protocol

Modules that perform expensive lookups register enrichers:

```lua
-- GeoIP module resolves once
ctx.enrich.geo = geoip.lookup(ctx.request.remote_addr)

-- Later modules read ctx.enrich.geo — never re-lookup
```

The engine provides `ctx:ensure("geo", fn)` to guarantee single execution.

## Policy Engine

Policies are evaluated in a dedicated pipeline stage (or inline module). Structure:

```
Policy
  ├── priority (lower = first)
  ├── enabled
  ├── conditions[] (AND within group, OR between groups)
  └── actions[]
```

### Condition Types

| Type | Example |
|------|---------|
| `host` | `api.example.com` |
| `path` | `/admin/*` |
| `method` | `POST` |
| `header` | `User-Agent contains bot` |
| `cookie` | `session exists` |
| `country` | `CN, RU` |
| `asn` | `AS13335` |
| `ip` | `203.0.113.0/24` |
| `cidr` | `10.0.0.0/8` |
| `trusted_bot` | `googlebot` |
| `bot_score` | `> 30` |
| `rate` | `> 100/min` |
| `fingerprint` | `known_bad` |
| `request_size` | `> 1MB` |
| `time` | `weekday 9-17` |
| `variable` | `${custom.flag} == true` |

### Action Types

`allow`, `continue`, `return_444`, `block`, `redirect`, `js_challenge`, `cookie_challenge`, `captcha`, `cache`, `rate_limit`, `log`, `tag`, `skip_module`, `skip_remaining`

## Configuration Flow

```
Dashboard (UI)
    │ REST
    ▼
API (validates, stores)
    │ PostgreSQL
    ▼
Worker (generates runtime artifacts)
    │ writes to shared volume / pushes to nodes
    ▼
Engine (in-memory reload via lua_code_cache + shared dict)
    │
    ▼
No nginx reload required for policies
```

Runtime artifacts:

- `sites/{id}/pipeline.json` — ordered module list
- `sites/{id}/policies.json` — compiled policy rules
- `modules/{name}/config.json` — per-site module config
- `shared/` — GeoIP DB, threat intel feeds

## Data Stores

| Store | Purpose | Environment |
|-------|---------|-------------|
| PostgreSQL | Sites, policies, users, certificates, audit | Production |
| SQLite | Same schema | Development |
| Redis | Rate limit counters, session state, cache metadata | All |
| Shared memory | Hot config, local counters, challenge tokens | Engine workers |
| Filesystem | GeoIP MMDB, generated nginx snippets (bootstrap only) | Engine nodes |

## Plugin System

Third-party modules live in `plugins/` or are loaded via Lua path:

```
plugins/my-module/
  ├── badsector.toml    # manifest
  ├── init.lua          # module implementation
  └── README.md
```

Manifest (`badsector.toml`):

```toml
[module]
name = "my-module"
version = "1.0.0"
description = "Custom security module"
author = "you"

[module.config]
schema = "schema.json"

[module.pipeline]
default_order = 500
phase = "request"  # request | response
```

The engine discovers plugins at startup and validates against the module interface.

## Observability

- **Request tracing** — Every module appends to `ctx.trace` with timing
- **Structured logs** — JSON to stdout or syslog
- **Metrics** — Prometheus endpoint on API/agent
- **Analytics** — Aggregated decision stats in PostgreSQL

## Deployment

| Method | Status |
|--------|--------|
| Docker Compose | Official, development and small production |
| Docker images | `badsector/engine`, `badsector/api`, etc. |
| Helm chart | Future Kubernetes support |
| badsector-agent | Optional sidecar for multi-node config sync |

## Security Boundaries

- API authenticated via JWT + RBAC
- Engine config read-only at runtime (API/worker writes)
- Secrets (TLS keys, API tokens) in vault/env, never in generated configs
- Coraza WAF runs late in pipeline (after cheap filters eliminate noise)

## Performance Budget

Per-request budget allocation:

| Stage | Budget |
|-------|--------|
| Context creation | 0.05ms |
| Access lists | 0.05ms |
| GeoIP (MMDB lookup) | 0.1ms |
| Policy evaluation (10 rules) | 0.3ms |
| Rate limit (Redis pipelined) | 0.2ms |
| **Total hot path target** | **< 1ms** |
| Coraza WAF | 1-5ms (only if reached) |
| Backend proxy | network bound |

Heavy modules (Coraza, behavior analysis) are placed late in the pipeline by design.
