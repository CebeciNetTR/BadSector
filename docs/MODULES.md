# Module Development Guide

## Built-in Modules

Implementation status as of latest development:

| Module | Status |
|--------|--------|
| access_lists | Implemented |
| trusted_bots | Implemented — statik prefix + rDNS + worker CIDR auto-sync |
| ip_reputation | Implemented |
| geoip | Implemented — MaxMind MMDB + worker sync |
| asn | Implemented — GeoLite2-ASN MMDB + ip_map |
| header_validation | Implemented |
| custom_rules | Implemented — safe expression DSL |
| policies | Implemented |
| rate_limiter | Implemented — see [RATE_LIMITER.md](RATE_LIMITER.md) |
| burst_detection | Implemented |
| js_challenge / cookie_challenge | Implemented — signed PoW; asset exclude; ban_threshold default 5 |
| threat_intel | Implemented |
| cache | Implemented (pass-through stub) |
| managed_waf | Implemented — see [MANAGED_WAF.md](MANAGED_WAF.md) |
| reverse_proxy | Implemented |

| Module | Phase | Description |
|--------|-------|-------------|
| `access_lists` | request | IP/CIDR allow and deny lists |
| `trusted_bots` | request | Verify legitimate crawlers (DNS/rDNS) |
| `ip_reputation` | request | Static/Redis blocklist (not a live threat-intel download; empty by default) |
| `geoip` | request | Resolve country/city from MMDB |
| `asn` | request | Resolve autonomous system |
| `header_validation` | request | Require/forbid headers |
| `custom_rules` | request | Safe inline expression rules |
| `behavior_analysis` | request | Anomaly scoring (expensive, optional) |
| `fingerprinting` | request | TLS/HTTP fingerprint matching |
| `rate_limiter` | request | **Implemented** — Token bucket / sliding window (Redis) |
| `burst_detection` | request | Short-window spike detection |
| `js_challenge` | request | Signed PoW; static assets skipped; document-only fail counter |
| `cookie_challenge` | request | Cookie validation challenge |
| `threat_intel` | request | External TI feed matching |
| `policies` | request | Policy engine evaluation |
| `cache` | request | Response caching |
| `managed_waf` | request | Coraza WAF integration |
| `reverse_proxy` | request | Upstream proxy (terminal: forwards) |

## Trusted Bots — doğrulama ve IP aralığı otomatik güncelleme

`trusted_bots` modülü, doğrulanmış arama motoru botlarını (Googlebot, Bingbot,
YandexBot, DuckDuckBot) tüm pipeline'dan (WAF, rate-limit, challenge dahil) muaf
tutar. Sahte UA'lı istekler muaf **değildir** — doğrulama katmanlıdır:

1. **UA eşleşmesi yoksa** → bot değil, normal pipeline (DNS'e gidilmez).
2. **IP resmi aralıktaysa** → doğru (DNS yok, hızlı yol).
3. **Aksi halde** → forward-confirmed rDNS (PTR → hostname suffix → A kaydı teyidi).

### Resmi IP aralıklarının günlük senkronizasyonu

Statik prefix'ler bayatlar. `badsector-worker`, GeoIP ile aynı desende resmi
yayınlanan aralıkları günlük indirir (`internal/bots`):

- Googlebot: `googlebot.json`, `special-crawlers.json`, `user-triggered-fetchers.json`
- Bingbot: `bingbot.json`

Sonuç `data/bots/bot-ranges.json` dosyasına yazılır; engine bunu ~60 sn'de bir
yeniden yükleyip **CIDR** eşleştirmesi yapar (IPv4 kesin, IPv6 4-bit/nibble
granülariteli). Bu dinamik liste hızlı yolda olduğu için **saldırı modunda da
DNS'siz** kullanılır — böylece saldırı sırasında meşru botlar yanlışlıkla
banlanmaz. YandexBot ve DuckDuckBot resmi makine-okunabilir liste yayınlamadığı
için statik prefix + rDNS ile doğrulanmaya devam eder.

| Öğe | Değer |
|-----|-------|
| Worker env | `BADSECTOR_BOTS_PATH` (vol), `BADSECTOR_BOT_SYNC_INTERVAL` (24h) |
| Engine env | `BADSECTOR_BOTS_PATH` (ro mount), `BADSECTOR_BOTS_RELOAD_SEC` (60) |
| Durum ucu | `GET /api/v1/bots/status` (son güncelleme + bot başına aralık sayısı) |
| Manuel tohumlama | `scripts/download-bots.sh` (jq gerekir) |

## Creating a Module

### 1. Implement the interface

```lua
-- engine/modules/example/init.lua
local decision = require("badsector.decision")

local M = {
    name = "example",
    version = "1.0.0",
}

function M.init(config)
    -- worker-level initialization
    -- load databases, compile patterns
end

function M.reload(config)
    -- hot reload handler
end

function M.run(ctx)
    -- fast path only
    if ctx.request.path:match("^/blocked") then
        ctx:trace("example", decision.BLOCK, "path matched block rule")
        return decision.block(403, "Forbidden")
    end

    ctx:trace("example", decision.CONTINUE, "no match")
    return decision.CONTINUE
end

return M
```

### 2. Register in site pipeline

Via API or dashboard — no code changes to core:

```json
{
  "pipeline": [
    { "module": "access_lists", "enabled": true },
    { "module": "geoip", "enabled": true },
    { "module": "example", "enabled": true, "config": { "threshold": 10 } }
  ]
}
```

### 3. Add configuration schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "threshold": { "type": "integer", "minimum": 1, "default": 10 }
  }
}
```

## Decision API

```lua
local decision = require("badsector.decision")

decision.CONTINUE                          -- non-terminal
decision.ALLOW                               -- terminal: skip to backend
decision.BLOCK                             -- terminal: 403 default
decision.block(status, body, headers)      -- terminal: custom block
decision.RETURN_444                        -- terminal: close connection
decision.redirect(url, status)             -- terminal: 302/301
decision.challenge("js", opts)             -- terminal: issue challenge
decision.cache(ttl, key)                   -- terminal: cache action
decision.custom(status, body, headers)     -- terminal: arbitrary response
decision.rate_limit(retry_after)           -- terminal: 429
```

## RequestContext Helpers

```lua
-- Lazy enrichment (runs once per request)
local geo = ctx:ensure("geo", function()
    return geoip.lookup(ctx.request.remote_addr)
end)

-- Custom variables for policies
ctx:set_var("risk_score", 42)
local score = ctx:get_var("risk_score")

-- Trace entry (automatic timing if using ctx:trace)
ctx:trace("module_name", decision, "human-readable reason")

-- Read enrichment from another module
if ctx.enrich.bot and ctx.enrich.bot.trusted then
    return decision.ALLOW
end
```

## Performance Rules

1. **No I/O in hot path** unless module explicitly requires it (and is placed late).
2. **Precompile** regex and patterns in `init()`, not `run()`.
3. **Use shared dict** for cross-worker state, Redis for cross-node.
4. **Fail open or closed** — configurable per module, default closed for security modules.
5. **Return CONTINUE** as fast as possible when no match.

## Testing

```bash
cd engine
busted spec/modules/example_spec.lua
```

Test harness provides mock `RequestContext` and config fixtures.

## Plugin Packaging

```
my-plugin/
├── badsector.toml
├── init.lua
├── schema.json
├── spec/
│   └── init_spec.lua
└── README.md
```

Install via CLI:

```bash
badsector-cli plugin install ./my-plugin
```
