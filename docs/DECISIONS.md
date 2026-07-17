# Architecture Decision Records

## ADR-001: OpenResty for Layer 7, HAProxy for Layer 4

**Status:** Accepted

All HTTP semantics and security decisions execute in OpenResty (Lua). HAProxy handles TLS, HTTP/2, HTTP/3, stick tables, and connection limits only.

**Rationale:** Separates expensive L7 logic from connection-level optimization. OpenResty provides mature Lua embedding with excellent performance. HAProxy excels at L4/L7 load balancing without request body inspection overhead in the TLS path.

---

## ADR-002: Module Pipeline with Terminal Decisions

**Status:** Accepted

Every module returns a typed decision. Terminal decisions halt execution immediately.

**Rationale:** Predictable performance budget. Cheap modules run first; expensive modules (Coraza WAF, behavior analysis) only execute when earlier filters pass.

---

## ADR-003: RequestContext as Event Bus

**Status:** Accepted

Modules share state via `RequestContext.enrich` and `ctx:ensure()`. No module-to-module imports.

**Rationale:** GeoIP, ASN, bot verification, and fingerprinting each resolve once. Eliminates duplicate MMDB lookups and DNS checks.

---

## ADR-004: Policy-Driven Configuration

**Status:** Accepted

Users configure policies (conditions + actions + priority). The API compiles to runtime JSON. No nginx syntax in the UI.

**Rationale:** Self-hosted Cloudflare-like UX. Reduces misconfiguration. Enables visual editor and explainable traces.

---

## ADR-005: Hot Reload Without nginx Reload

**Status:** Accepted

Policy and module config reload via Lua `reload()` hooks and atomic shared-memory swap. Bootstrap nginx.conf is static.

**Rationale:** Zero-downtime policy updates. nginx reload drops keepalive connections and clears caches.

---

## ADR-006: Go for Control Plane

**Status:** Accepted

API, worker, CLI, and agent written in Go. Engine in Lua (OpenResty).

**Rationale:** Go provides strong concurrency for API/worker, single binary deployment, and shared internal packages between services.

---

## ADR-007: Redis for Counters, PostgreSQL for Config

**Status:** Accepted

Rate limiting and burst detection use Redis. Sites, policies, certificates, and audit logs use PostgreSQL (SQLite in dev).

**Rationale:** Redis provides atomic increment with TTL at scale. PostgreSQL provides relational integrity for configuration and analytics.

---

## ADR-008: Plugin System as First-Class Citizen

**Status:** Accepted

Third-party modules live in `plugins/` with `badsector.toml` manifest. Same interface as built-in modules.

**Rationale:** Extensibility without core modifications. Community can ship modules independently.

---

## ADR-009: Flood Hardening — Edge Ban Cache + Host ipset + Localhost Data Plane

**Status:** Accepted (2026-07)

1. **Engine ban lookup** uses `lua_shared_dict` negative cache; health/ACME never touch Redis.
2. **HAProxy** flushes IP hit counters to Redis in **pipeline batches** (not per-IP round-trips).
3. **Watcher** bans abusive IPs at **host ipset/iptables** (all ports) + Redis; must not crash-loop on Redis blips.
4. **Redis/Postgres/API** publish only on **127.0.0.1** in compose — never expose passwordless Redis to the internet.
5. **JS challenge** auto-ban counts only document navigations; static assets are excluded (favicon false-ban).

**Rationale:** A flood of tens of thousands of distinct IPs saturated Redis and flipped HAProxy engine health to DOWN. Separating health from Redis, caching ban misses, batching edge writes, and closing data-plane ports restores survivability on modest hardware (e.g. 4c/8GB). Host-level ipset remains the cheapest drop after threshold.

**Trade-off:** Watcher DROP can lock out SSH for a banned admin IP — mitigate with alternate IP/KVM and future admin whitelist.

---

## ADR-010: Pipeline UI Owns Order/Enabled Only

**Status:** Accepted (2026-07)

Saving the Pipeline page must **not** overwrite module JSON config with browser placeholder defaults. Server keeps existing stage config; GORM must persist `Enabled=false` (no `default:true` zero-value skip).

**Rationale:** Operators disabled modules in UI only to see them re-enabled after save; GeoIP allow-lists were wiped by `DEFAULT_MODULE_CONFIG` payloads.
