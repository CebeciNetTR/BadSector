# Changelog

All notable changes to BadSector are documented here.

## [Unreleased]

### Security / Hardening

- **Redis / Postgres / API artık internete kapalı** — Compose portları `127.0.0.1` bind; şifresiz Redis dışarıdan erişilemez (önceki Cross-Protocol / FLUSHALL riski).
- **Tüm servislere `restart: unless-stopped`** — Redis/API/UI çökünce kendiliğinden ayağa kalkar.
- **Flood dayanıklılığı (engine)** — Health/ACME/reload Redis ban check'ten önce döner (HAProxy engine DOWN zinciri kırıldı). Ban lookup `lua_shared_dict badsector_bans` negatif cache (~5s). ([DEPLOY.md](docs/DEPLOY.md), [ARCHITECTURE.md](docs/ARCHITECTURE.md))
- **HAProxy `flush_hits` pipeline** — 80k+ IP'de tek tek ZINCRBY yerine 1000'lik batch (Redis boğulması).
- **Watcher** — `set -e` kaldırıldı (Redis kısa düşüşünde crash-loop yok); ipset `maxelem` 1M.

### Fixed

- **Client IP spoof** — `BADSECTOR_CLOUDFLARE=false` (varsayılan): HAProxy spoof header siler, `X-Real-IP=%[src]`; engine CF/XFF okumaz. `true`: CF-Connecting-IP güvenilir (entrypoint `haproxy.cfg` CLIENT_IP_POLICY bloğunu yamar; `include` kullanılmaz).
- **JS PoW SHA-256** — İstemci script'i `h` state'ini cache'leyip bozuyordu (2. hash'ten itibaren yanlış); IV artık her çağrıda kopyalanır.
- **Pipeline tik kaldırma kaybolmuyordu** — GORM `Enabled bool` + `default:true` false değerini DB'ye yazmıyordu; Create'te `Select` + model tag düzeltmesi. Pipeline kaydı artık config göndermez (placeholder GeoIP ezmesi yok).
- **JS challenge favicon ban** — `/favicon.ico` ve statik asset'ler challenge dışı; ban sayacı yalnızca belge navigasyonunda artar. Eşik varsayılan **5**. PoW sonrası boş 302/`block` flash'i → düzgün REDIRECT + Set-Cookie.

### Changed

- **Donanım varsayımları → 8c / 24GB (OVH edge)** — Redis `maxmemory 2gb`; Postgres `shared_buffers=1GB` / `effective_cache_size=4GB`; HAProxy `nbthread 8`, `maxconn 100000`, stick-table 2m; engine `worker_connections 16384` + büyütülmüş lua_shared_dict; watcher `BAN_TTL=7200`.
- **Admin UI portu** — `.env` ile `BADSECTOR_UI_PORT` (varsayılan 3000).
- **JS challenge** — `ban_threshold` 3→5; ban Redis değeri `js_challenge` (kaynak ayrımı).

### Added

- **Backup / Restore** — Panel + `GET /backup` / `POST /backup/restore`: DB + TLS certs + optional `secrets.env`. Secrets: `keep` \| `rotate` \| `skip`. Scripts: `scripts/backup.sh`, `scripts/restore.sh`. ([BACKUP.md](docs/BACKUP.md))
- **Trusted IPs** — `BADSECTOR_TRUSTED_IPS` (env, kodda sabit IP yok): iptables ACCEPT, watcher/HAProxy ban muaf, engine pipeline/GeoIP/challenge bypass. `scripts/clear-bans.sh` ile toplu ban temizliği.
- **GeoIP challenge fail → ban** — `deny_action=challenge` iken 60 sn / `ban_threshold` (varsayılan 5) çözümsüz belge → `bs:ban:<ip>=geoip_challenge`. TR allow etkilenmez; favicon/statik sayılmaz. Ayrı `js_challenge` gerekmez.
- **GeoIP `deny_action`** — Allow-list dışı / block list için `block` (403), `drop` (444), `challenge` (JS PoW). Challenge sonrası `bs_pass` GeoIP’de de doğrulanır (döngü yok). UI + engine.
- **Ortak JS challenge HTML** — Site template boşken `data/challenge/template.html` (gitignore; GitHub'da yok). Compose mount + `BADSECTOR_JS_CHALLENGE_TEMPLATE_PATH`.
- **İmzalı Proof-of-Work JS challenge** — Taklit edilebilen eski "cookie=1" mantığı, stateless HMAC-SHA256 imzalı PoW ile değiştirildi (`engine/lib/badsector/crypto.lua`, `pow.lua`). İstemci senkron SHA-256 ile çözer; sunucu 1 hash ile doğrular ve imzalı `bs_pass` gecis cookie'si verir (hızlı yol, ~µs). Zorluk attack mode'da otomatik yükselir. HAProxy edge fast-path: `bs_pass` taşıyanlar attack-429'undan muaf. `BADSECTOR_CHALLENGE_SECRET` env (üretimde değiştirin). ([SECURITY_MODULES.md](docs/SECURITY_MODULES.md))
- **Trusted bot IP auto-sync** — Worker günlük olarak Googlebot/Bingbot resmi IP aralıklarını indirir (`internal/bots`), engine bunları CIDR (IPv4 kesin + IPv6) eşleştirmesiyle doğrular. `GET /bots/status`, `./data/bots` mount, `scripts/download-bots.sh`. Statik hardcoded prefix'ler artık taze tutuluyor ve saldırı modunda da (DNS'siz) kullanılıyor.
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
