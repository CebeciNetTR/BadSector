# Managed WAF Module (Coraza)

The `managed_waf` pipeline module integrates [Coraza WAF](https://coraza.io/) as a late-stage filter — after cheap modules (access lists, geoip, rate limit) and before cache/reverse proxy.

## Pipeline Placement

```
… → Rate Limiter → managed_waf → Reverse Proxy → Backend
```

Default: **included but disabled** on new sites. Enable via dashboard or API.

## Architecture

```
managed_waf.lua
       │
       ▼
  coraza.lua (engine abstraction)
       │
       ├── Coraza native (production) — require("coraza") or require("resty.coraza")
       └── Built-in rules (development) — CRS-inspired patterns when Coraza unavailable
```

## Configuration

```json
{
  "ruleset": "coraza-crs",
  "paranoia_level": 1,
  "mode": "block",
  "exclude_paths": ["/badsector/health"],
  "audit": true,
  "rules_dir": "/etc/badsector/coraza/rules"
}
```

| Field | Description |
|-------|-------------|
| `ruleset` | Ruleset name (used by Coraza engine) |
| `paranoia_level` | 1–4, filters built-in rules; passed to Coraza CRS |
| `mode` | `block` → 403 on match; `detect` → log and continue |
| `exclude_paths` | Path prefixes skipped by WAF |
| `audit` | Write matches to nginx error log |
| `rules_dir` | CRS rule files directory (production) |

## Decision Flow

| Match | Mode | Result |
|-------|------|--------|
| No | any | `CONTINUE` |
| Yes | `detect` | `CONTINUE` + log + `ctx.enrich.waf` |
| Yes | `block` | `BLOCK` 403 + `X-BadSector-WAF-Rule` header |

## RequestContext Enrichment

After scan:

```lua
ctx.enrich.waf = {
  matched = true,
  rule_id = "942100",
  message = "SQL Injection",
  zone = "query",
  backend = "builtin" | "coraza",
}
ctx:set_var("waf_matched", true)
ctx:set_var("waf_rule_id", "942100")
```

## Trace Example

```json
{
  "module": "managed_waf",
  "decision": "BLOCK",
  "detail": "Rule 942100: SQL Injection (zone: query)",
  "rule_id": "942100",
  "mode": "block"
}
```

## Production Setup

1. Install Coraza OpenResty bindings in the engine image
2. Mount OWASP CRS rules to `/etc/badsector/coraza/rules`
3. Enable module per site in dashboard (**Managed WAF** or Pipeline)
4. Start with `mode: detect`, then switch to `block`

### Docker volume example

```yaml
engine:
  volumes:
    - ./coraza/rules:/etc/badsector/coraza/rules:ro
```

## API

| Method | Path |
|--------|------|
| GET | `/api/v1/sites/:id/managed-waf` |
| PUT | `/api/v1/sites/:id/managed-waf` |

## Built-in Rules (Development)

When Coraza is not installed, these patterns are checked:

| Rule ID | Level | Description |
|---------|-------|-------------|
| 942100 | 1 | SQL Injection |
| 941100 | 1 | XSS |
| 930100 | 1 | Path traversal |
| 920450 | 2 | Null byte |
| 932100 | 2 | Command injection |

## Performance Note

WAF runs **late** in the pipeline by design. Budget: 1–5ms when Coraza is active. Place after rate limiting to reduce scanned request volume.
