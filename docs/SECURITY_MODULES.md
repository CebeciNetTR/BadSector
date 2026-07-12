# Edge Security Modules

ASN filtering, header validation, burst detection, and browser challenges.

Configure via Dashboard **Edge Security** (`/security-modules`) or REST API. Saving triggers runtime regenerate + engine hot reload.

## GeoIP (`geoip`)

Country lookup via **GeoLite2-Country.mmdb** (worker auto-download). Optional header fallback when MMDB is missing.

| Field | Description |
|-------|-------------|
| `database_path` | Path to Country MMDB |
| `block_countries` | ISO codes to block (e.g. `CN`, `RU`) |
| `allow_countries` | Used with `allow_only: true` |
| `allow_only` | Only listed countries pass |
| `use_header_fallback` | Use `CF-IPCountry` / `X-Country-Code` if lookup fails |
| `fail_open` | Continue if country unknown |

Sets `ctx.vars.country` and `ctx.enrich.geo`. See [GEOIP.md](GEOIP.md).

## Custom Rules (`custom_rules`)

Inline rules evaluated in the pipeline before or after policies (configure order in Pipeline page).

Uses a **safe expression DSL** — not arbitrary Lua (`loadstring` is never used).

| Field | Description |
|-------|-------------|
| `rules[].match.expr` | Expression string |
| `rules[].action` | `block`, `allow`, `rate_limit`, `redirect`, `log` |
| `fail_open` | Continue on evaluation errors |

**Expression examples:**

```
path.starts_with("/admin")
country in ["TR", "DE"]
header.User-Agent contains "curl"
ip == "1.2.3.4" and method == "POST"
```

API: `GET/PUT /api/v1/sites/:id/custom-rules`

## ASN (`asn`)

Resolves ASN from **GeoLite2-ASN.mmdb** with `ip_map` overrides. Supports block/allow lists.

| Field | Description |
|-------|-------------|
| `block_asns` | Block requests from these ASN numbers |
| `allow_asns` | Used with `allow_only: true` |
| `allow_only` | If true, only ASNs in `allow_asns` may pass |
| `database_path` | Path to ASN MMDB |
| `ip_map` | Manual IP → ASN overrides |
| `fail_open` | Continue if ASN unknown |

Sets `ctx.vars.asn` and `ctx.enrich.asn`.

## Header Validation (`header_validation`)

| Field | Description |
|-------|-------------|
| `required` | Global required header names |
| `forbidden` | Global forbidden header names |
| `rules` | Per-path rules: `{ "header", "required", "forbidden", "pattern", "paths" }` |

Case-insensitive header lookup. Missing required → 400; forbidden → 403.

## Burst Detection (`burst_detection`)

Short-window spike detection using Redis (same INCR+EXPIRE as rate limiter).

| Field | Default | Description |
|-------|---------|-------------|
| `window` | 10 | Seconds |
| `threshold` | 50 | Max requests in window |
| `key_by` | `ip` | `ip`, `ip_path`, `global` |
| `paths` | `["/*"]` | Path patterns |
| `action` | `rate_limit` | `rate_limit` (429) or `block` |
| `fail_open` | true | Continue if Redis down |

## JS Challenge (`js_challenge`)

Serves HTML+JS page that sets a cookie, then reloads. Disabled by default.

| Field | Description |
|-------|-------------|
| `paths` | Apply challenge to these paths |
| `exclude_paths` | Skip (default `/badsector/*`) |
| `cookie_name` | Default `bs_js_ok` |
| `cookie_ttl` | Max-Age seconds |

> [!NOTE]
> **Automated Redis Ban**: If a client triggers the JS challenge more than 5 times in a 1-minute window without solving it, their IP is automatically banned in Redis for 2 hours (7200 seconds). Subsequent requests will be closed instantly with HTTP `444`.

## Cookie Challenge (`cookie_challenge`)

Sets HttpOnly verification cookie on first visit; subsequent requests pass.

| Field | Description |
|-------|-------------|
| `cookie_name` | Default `bs_verified` |
| `cookie_ttl` | Cookie Max-Age |

> [!NOTE]
> **Automated Redis Ban**: If a client triggers the Cookie challenge more than 5 times in a 1-minute window without the verified cookie, their IP is automatically banned in Redis for 2 hours (7200 seconds). Subsequent requests will be closed instantly with HTTP `444`.

## API

| Module | GET | PUT |
|--------|-----|-----|
| ASN | `/sites/:id/asn` | `/sites/:id/asn` |
| Header validation | `/sites/:id/header-validation` | `/sites/:id/header-validation` |
| Burst detection | `/sites/:id/burst-detection` | `/sites/:id/burst-detection` |
| JS challenge | `/sites/:id/js-challenge` | `/sites/:id/js-challenge` |
| Cookie challenge | `/sites/:id/cookie-challenge` | `/sites/:id/cookie-challenge` |

Request body:

```json
{
  "enabled": true,
  "config": { }
}
```

If the module is not in the site pipeline, PUT creates a stage before `reverse_proxy`.

## Pipeline placement (recommended)

```
access_lists → trusted_bots → ip_reputation → geoip → asn
→ header_validation → policies → burst_detection → rate_limiter
→ js_challenge / cookie_challenge → managed_waf → reverse_proxy
```

Challenges are expensive — place late but before WAF if used for bot mitigation.

## Testing

```bash
# Burst (lower threshold in UI first)
for i in $(seq 1 60); do curl -s -o /dev/null -H "Host: localhost" http://localhost:9080/; done

# Header validation — require User-Agent, then:
curl -H "Host: localhost" -H "User-Agent: test" http://localhost:9080/

# JS challenge — enable in UI, then browser or curl without cookie
curl -H "Host: localhost" http://localhost:9080/
```
