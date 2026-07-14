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

## JS Challenge — imzalı Proof-of-Work (`js_challenge`)

Varsayılan kapalı. Artık **kriptografik imzalı Proof-of-Work** kullanır (eski
"cookie=1 set et" mantığı taklit edilebilirdi). Tamamen **stateless**'tır —
Redis/DB'de challenge state tutulmaz; doğrulama yalnızca HMAC + zaman + PoW
teyididir.

**Akış:**
1. Cookie yoksa → tarayıcıya imzalı challenge token'lı bir sayfa döner. Tarayıcı
   senkron SHA-256 ile `sha256(token:nonce)` başında `difficulty` adet hex sıfır
   olacak bir `nonce` bulur (PoW maliyetini **istemci** öder).
2. Çözümü `bs_pow` cookie'sine yazıp yeniler. Sunucu **1 hash** ile doğrular,
   imzalı `bs_pass` gecis cookie'si verir (302).
3. Sonraki istekler `bs_pass` ile **1 HMAC** (~µs) doğrulanır → hızlı yol.

**Token'lar (stateless HMAC-SHA256):**
- Challenge: `ts.d.salt.sig`, `sig = HMAC(secret, "chal|"+ip+"|ts.d.salt")` — `difficulty` imzalı olduğundan istemci düşüremez.
- Pass: `exp.sig`, `sig = HMAC(secret, "pass|"+ip+"|ua_fp|exp")` — IP + UA'ya bağlı.

| Field | Default | Description |
|-------|---------|-------------|
| `paths` / `exclude_paths` | `/*` / `/badsector/*` | Uygulama kapsamı |
| `difficulty` | 4 | Normal zorluk (başta hex sıfır ≈ 2^16 hash) |
| `difficulty_attack` | 5 | Attack mode'da otomatik yükselen zorluk (≈ 2^20) |
| `pass_ttl` | 3600 | `bs_pass` geçerlilik (s) |
| `pass_cookie` / `pow_cookie` | `bs_pass` / `bs_pow` | Cookie adları |
| `ban_threshold` / `ban_ttl` | 3 / 86400 | Çözümsüz challenge banı |

**Env (engine):** `BADSECTOR_CHALLENGE_SECRET` (üretimde mutlaka değiştirin; tüm
worker'lar aynı sırrı paylaşmalı), `BADSECTOR_POW_DIFFICULTY[_ATTACK]`,
`BADSECTOR_POW_PASS_TTL`, `BADSECTOR_POW_CHAL_TTL`.

**Edge fast-path:** `bs_pass` taşıyan istekler HAProxy'de attack-mode 429'undan
muaf (presence kontrolü); gerçek kriptografik doğrulama motorda yapılır, sahte
cookie kötüye kullanımı auto-ban ile IP başına sınırlıdır.

**Difficulty maliyeti (attack mode):** PoW'u istemci çözer; sunucu tarafı maliyet
challenge başına ~1 HMAC + 1 hash (~µs). Asıl maliyet TLS handshake + sayfa
egress'idir ve auto-ban sayesinde IP başına birkaç istekle sınırlıdır.

> [!NOTE]
> **Otomatik ban**: Bir istemci 60 sn içinde `ban_threshold` (varsayılan 3) kez
> challenge alıp çözemezse IP'si 24 saat banlanır; sonraki istekler edge'de
> sessizce düşürülür (silent-drop).

> [!IMPORTANT]
> PoW gerçek bir tarayıcı (JavaScript + SHA-256) gerektirir. JS çalıştırmayan
> istemciler (bazı botlar, JS'siz tarayıcılar) çözemez ve auto-ban'a takılır —
> meşru botlar için `trusted_bots` muafiyetine güvenin.

## Cookie Challenge (`cookie_challenge`)

Sets HttpOnly verification cookie on first visit; subsequent requests pass.

| Field | Description |
|-------|-------------|
| `cookie_name` | Default `bs_verified` |
| `cookie_ttl` | Cookie Max-Age |

> [!NOTE]
> **Automated Redis Ban**: If a client triggers the Cookie challenge more than 2 times in a 1-minute window without the verified cookie, their IP is automatically banned in Redis for 24 hours (86400 seconds). Subsequent requests will be closed instantly with HTTP `444`.

## HAProxy-level IP Watcher & Attack Mode

To handle massive DDoS floods without exhausting OpenResty (engine) resources:

1. **HAProxy Lua Ban Check**: When attack mode is enabled (`redis-cli set bs:attack_mode 1`), HAProxy checks Redis for `bs:ban:<ip>` on every request and silently drops banned IPs (`http-request silent-drop`) without passing them to the engine or wasting port resources.
2. **IP Watcher Service**: A privileged daemon container that monitors HAProxy request hit counters in Redis (`bs:ip_hits`). If an IP exceeds `BAN_THRESHOLD` (default 1000 hits in 30s), the watcher automatically bans the IP for 24 hours in both the host firewall via `iptables` / `ipset` (zero CPU overhead) and Redis.
3. **Daily Reset**: Every day at midnight (00:00), the watcher resets hit counters and flushes the host `ipset` blocklist.

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
