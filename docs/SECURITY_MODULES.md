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
| `deny_action` | `block` (403) \| `drop` (444) \| `challenge` (JS PoW). Default `block`. |
| `attack_block_countries` | Attack modunda kernel block listesi → `ipset bs_attack_geo` (TLS/HAProxy öncesi). `allow_only` attack modunda kernel'e yansımaz. |
| `ban_threshold` / `ban_ttl` | Challenge fail → ban (default 5 / 60s window, TTL 86400). Redis: `geoip_challenge` |

Sets `ctx.vars.country` and `ctx.enrich.geo`. See [GEOIP.md](GEOIP.md).

**`deny_action=challenge`:** TR (allow) serbest; yabancı PoW görür. Ayrı `js_challenge` modülü gerekmez. 60 sn içinde `ban_threshold` çözümsüz belge → ban. Statik asset sayılmaz.

**Attack mode (kernel block list):** `bs:attack_mode=1` iken watcher yalnızca **açık block listesindeki** ülkeleri düşürür (`attack_block_countries` + `block_countries` → ipdeny CIDR → `ipset bs_attack_geo`). `allow_only` attack modunda devreye girmez — normal modda TR/challenge davranışı ayrı kalır. TR exempt (yanlışlıkla block listesine yazılsa bile kernel'de düşmez).

Engine: attack modunda yine yalnızca block listesi uygulanır (allow_only atlanır); kaçan paketler için yedek.

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
| `attack_deny_action` | Engine yedek: attack modunda ASN red eylemi. |
| `attack_block_asns` | Attack modunda kernel ban (hit≥1 + ASN eşleşmesi → `bs_banned`) + engine drop |
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
   imzalı `bs_pass` geçiş cookie'si verir (**302 REDIRECT** + `Set-Cookie`).
3. Sonraki istekler `bs_pass` ile **1 HMAC** (~µs) doğrulanır → hızlı yol.

**Token'lar (stateless HMAC-SHA256):**
- Challenge: `ts.d.salt.sig`, `sig = HMAC(secret, "chal|"+ip+"|ts.d.salt")` — `difficulty` imzalı olduğundan istemci düşüremez.
- Pass: `exp.sig`, `sig = HMAC(secret, "pass|"+ip+"|ua_fp|exp")` — IP + UA'ya bağlı.

| Field | Default | Description |
|-------|---------|-------------|
| `paths` / `exclude_paths` | `/*` / `/badsector/*`, favicon, robots… | Uygulama kapsamı |
| `difficulty` | 4 | Normal zorluk (başta hex sıfır ≈ 2^16 hash) |
| `difficulty_attack` | 5 | Attack mode'da otomatik yükselen zorluk (≈ 2^20) |
| `pass_ttl` | 3600 | `bs_pass` geçerlilik (s) |
| `pass_cookie` / `pow_cookie` | `bs_pass` / `bs_pow` | Cookie adları |
| `ban_threshold` / `ban_ttl` | **5** / 86400 | Çözümsüz challenge banı (60s pencere) |
| `template` | `""` | Site özel HTML (boş → global dosya → yerleşik varsayılan) |

**Ortak HTML (tüm siteler, GitHub'da görünmez):** Sunucuda
`data/challenge/template.html` oluşturun (compose → `/etc/badsector/challenge/template.html`).
Site `template` boşken engine bu dosyayı kullanır. `template.html` gitignore'dadır;
yalnızca `template.html.example` + README repoda. Bkz. `data/challenge/README.md`.

**Statik asset muafiyeti (önemli):** `favicon.ico`, `*.css`, `*.js`, `*.png` vb. uzantılar
ve varsayılan exclude listesi **challenge almaz** ve ban sayacına yazılmaz. Aksi halde
tek sayfa yükü (HTML + favicon) sayacı doldurup meşru IP'yi banlardı.

**Ban sayacı:** Yalnızca belge navigasyonu (`Sec-Fetch-Dest: document` veya
`Accept: text/html`) ve geçersiz PoW çözümünde artar. Redis ban değeri:
`bs:ban:<ip> = "js_challenge"` (watcher ban'ından ayırt etmek için).

**Özel challenge sayfası (`template`):** Panelden (Edge Security → Challenges → JS
Challenge) tam HTML/CSS yazılabilir — site bazında global dosyayı ezer. Görünür markup
tamamen sizindir; PoW çözücü `<script>` engine tarafından her zaman otomatik enjekte
edilir (`</body>` varsa öncesine, yoksa sona). Şablon `string.format` ile değil düz
string olarak işlenir, CSS'teki `%` kaçırmanız gerekmez. `{{difficulty}}` yer tutucusu
geçerli zorluk sayısıyla değiştirilir.

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
> **Otomatik ban**: Bir istemci 60 sn içinde `ban_threshold` (varsayılan **5**) kez
> *belge* challenge'ı alıp çözemezse IP Redis'te 24 saat banlanır
> (`bs:ban:<ip>`). Attack mode açıkken HAProxy silent-drop uygular; kapalıyken
> engine erken drop eder. **Watcher iptables ban'ından farklıdır** (ipset'te olmayabilir).

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

1. **HAProxy Lua Ban Check** (`deploy/haproxy/lua/ban_check.lua`): Attack mode açıkken (`bs:attack_mode=1`) bellekteki ban tablosunu okur; banlı IP'leri `silent-drop` eder. Hit sayaçlarını arka planda Redis'e **pipeline batch** ile yazar (80k+ IP flood'da Redis'i boğmamak için).
2. **IP Watcher** (`deploy/watcher`): `bs:ip_hits` sorted set'ini izler. Eşik aşılınca (`BAN_THRESHOLD`, varsayılan 1000 — kümülatif, gece sıfırlanır) IP'yi **host ipset** (`bs_banned`, `maxelem` 1M) + Redis `bs:ban:<ip>` ile banlar. Ban TTL: `BAN_TTL` (compose varsayılan 7200). `network_mode: host` + `privileged` — iptables host'a yazılır; konteyner dursa bile kural kalır (reboot temizler).
3. **Stale prune**: HAProxy flush her IP için `bs:ip_seen` (unix last-seen) yazar. Watcher her turda: `hit < HIT_MIN_KEEP` (10) **ve** son görülme `HIT_STALE_SEC` (600s) eskiyse veya `bs:ip_seen` yoksa → `ZREM`. Aktif / yüksek hit IP’ler kalır.
4. **Daily Reset**: Gece 00:00'da `bs:ip_hits` + `bs:ip_seen` ve ipset flush. Redis kısa süre erişilemez olsa watcher **crash-loop yapmaz** (`set -e` yok).
5. **Engine ban cache**: `init.lua` istek başına Redis GET yerine shared-dict negatif cache kullanır; `/badsector/health` Redis'e dokunmaz.

### Ban kaynağını teşhis

```bash
IP=1.2.3.4
docker compose exec -T redis redis-cli get "bs:ban:$IP"    # "js_challenge" veya "1"
docker compose exec -T redis redis-cli ttl "bs:ban:$IP"
docker compose exec -T redis redis-cli get "bs:js_fail:$IP"
docker compose exec -T redis redis-cli zscore bs:ip_hits "$IP"
sudo ipset test bs_banned "$IP"                            # watcher ise burada olur
docker compose logs --since 2h engine | grep -iE "banland|$IP"
docker compose logs --since 2h watcher | grep -iE "BANNED|$IP"
```

| Bulgu | Kaynak |
|--------|--------|
| Engine log `cozumsuz JS challenge` / Redis değeri `js_challenge` | JS challenge auto-ban |
| Watcher log `BANNED` + ipset'te | Watcher (hit eşiği) |
| Sadece Redis, ipset yok | Challenge / cookie ban (iptables yok) |

> [!WARNING]
> Watcher iptables DROP **tüm portları** (SSH dahil) keser. Admin IP'yi yanlışlıkla
> eşiğe sokarsanız SSH kilitlenebilir — farklı IP / VPN / sağlayıcı KVM ile girip
> `ipset flush bs_banned` veya `docker compose stop watcher` yapın.

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
