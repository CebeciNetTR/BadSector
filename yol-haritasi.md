# BadSector — Yol Haritası

> Self-Hosted Edge Security Platform.
> Bu belge projenin **tamamlanan** ve **eksik kalan** bölümlerini takip eder.
> Son güncelleme: 2026-07-14

## En Son Yapılan İş

- **İmzalı Proof-of-Work JS challenge (stateless HMAC + JS PoW + edge fast-path + otomatik difficulty).**
  - Eski taklit edilebilir "cookie=1" challenge'ı gerçek kriptografik PoW ile değiştirildi. Yeni dosyalar: `engine/lib/badsector/crypto.lua` (HMAC-SHA256, resty.sha256 üzerine), `engine/lib/badsector/pow.lua` (imzalı challenge/pass token, difficulty auto).
  - `challenge.lua` artık senkron SHA-256 çözücülü PoW sayfası render ediyor; `modules/js_challenge.lua` pass-doğrula → çözüm-doğrula → challenge-üret akışına geçti.
  - **Stateless:** Redis/DB'de state yok; doğrulama = HMAC + zaman + 1 hash. **Edge fast-path:** HAProxy'de `bs_pass` taşıyanlar attack-429'dan muaf (`haproxy-live.cfg`), gerçek doğrulama motorda. **Difficulty auto:** attack mode'da 4→5 (config'lenebilir).
  - `BADSECTOR_CHALLENGE_SECRET` env (compose'da; **üretimde değiştir**). API: `DefaultJsChallengeConfig` PoW alanları.
  - **Kalan (bilinçli):** `cookie_challenge` modülü hâlâ eski (zayıf) doğrulamada — istenirse aynı imzalı yapıya taşınabilir. PoW gerçek tarayıcı (JS+SHA-256) ister; JS'siz meşru istemciler için `trusted_bots` muafiyetine güvenilir. Edge tarafı presence-bypass; native-HMAC edge doğrulaması ileride sertleştirme adımı.

### Önceki iş
- **Trusted bot IP aralıkları otomatik güncelleniyor (GeoIP gibi günlük).**
  - Worker artık Googlebot (`googlebot`, `special-crawlers`, `user-triggered-fetchers`) ve Bingbot resmi IP aralıklarını günlük indirip `data/bots/bot-ranges.json`'a yazıyor (`internal/bots/sync.go`).
  - Engine bu dosyayı ~60 sn'de bir yükleyip **CIDR** eşleştirmesi yapıyor (IPv4 kesin + IPv6 nibble); statik hardcoded prefix'lerin bayatlaması sorunu çözüldü. Dinamik liste hızlı yolda olduğu için **saldırı modunda da DNS'siz** kullanılıyor (`engine/lib/badsector/bot_verify.lua`).
  - `GET /api/v1/bots/status` durum ucu, `./data/bots` mount (worker rw / engine+api ro), `scripts/download-bots.sh` manuel tohumlama.
  - **Kalan (bilinçli):** YandexBot & DuckDuckBot resmi JSON yayınlamadığı için statik prefix + rDNS ile kalıyor; IPv6 eşleşme 4-bit granülariteli (bot prefix'leri /32,/48,/64 olduğu için sorun değil).

### Daha önce
- **Dashboard'a "Banlı IP" ve "İzlenen IP" kartları eklendi.**
  - Go API artık `bs:ban:*` anahtarlarını `SCAN` ile sayıyor (`internal/metrics/store.go` → `scanCount`), izlenen IP sayısını `ZCARD bs:ip_hits` ile alıyor.
  - Engine erken drop yolları (`init.lua`) artık sayaç yazıyor: `metrics.incr("BAN_DROP")` / `metrics.incr("NO_SITE")` → "Karar Dağılımı"nda görünür.
  - Dosyalar: `internal/metrics/store.go`, `internal/handler/metrics.go`, `ui/src/types/metrics.ts`, `ui/src/pages/Dashboard.tsx`, `engine/lib/badsector/metrics.lua`, `engine/lib/badsector/init.lua`.
  - **Neden:** Ban altyapısı (watcher + HAProxy edge) metriklerden ayrı bir alt sistemdi; 556 banlı IP varken UI 0 gösteriyordu. Bu sorun çözüldü.

### Bir sonraki mantıklı adım
- HAProxy edge tarafındaki silent-drop / 429 sayısını periyodik olarak Redis'e yazıp dashboard'a **"Edge'de Engellenen"** kartı olarak eklemek (attack mode açıkken edge'de düşen trafik hâlâ "Toplam İstek" sayacına yansımıyor).

---

## Bileşenler (Components)

| Bileşen | Durum | Not |
|---------|-------|-----|
| **badsector-engine** (OpenResty/Lua) | ✅ Tamamlandı | Pipeline executor, RequestContext, karar tipleri, hot reload |
| **badsector-api** (Go REST) | ✅ Tamamlandı | Sites, policies, pipeline, rate-limit, WAF, sertifika, metrik uçları + JWT |
| **badsector-ui** (React) | 🟡 Kısmen | 9 sayfa gerçek, 5 sayfa henüz "Coming soon" placeholder |
| **badsector-worker** (Go) | ✅ Tamamlandı | GeoIP/threat-intel/sertifika yenileme; `internal/certs` import sorunu çözüldü |
| **badsector-agent** (Go) | 🟡 İskelet | Yalnızca `/health` var; config sync + metrik raporlama eksik |
| **badsector-cli** (Go/cobra) | 🟡 İskelet | Komut ağacı var; HTTP çağrıları "future PR" olarak stub |

---

## Modüller (Pipeline Modules)

| Modül | Durum | Dosya |
|-------|-------|-------|
| Access Lists | ✅ | `engine/lib/badsector/modules/access_lists.lua` |
| Trusted Bots | ✅ | `modules/trusted_bots.lua` |
| IP Reputation | ✅ | `modules/ip_reputation.lua` |
| GeoIP | ✅ | `modules/geoip.lua` (MaxMind MMDB + worker sync) |
| ASN | ✅ | `modules/asn.lua` |
| Header Validation | ✅ | `modules/header_validation.lua` |
| Custom Rules | ✅ | `modules/custom_rules.lua` (güvenli ifade DSL) |
| Rate Limiter | ✅ | `modules/rate_limiter.lua` (Redis + shared dict) |
| Burst Detection | ✅ | `modules/burst_detection.lua` |
| JS Challenge | ✅ | `modules/js_challenge.lua` |
| Cookie Challenge | ✅ | `modules/cookie_challenge.lua` |
| Threat Intelligence | ✅ | `modules/threat_intel.lua` (motor tarafı) |
| Cache | ✅ | `modules/cache.lua` |
| Managed WAF (Coraza) | ✅ | `modules/managed_waf.lua` + `coraza.lua` |
| Reverse Proxy | ✅ | `modules/reverse_proxy.lua` (dinamik backend URL) |
| Policies | ✅ | `modules/policies.lua` |
| **Behavior Analysis** | ❌ Eksik | Spec'te var, modül yok |
| **Fingerprinting** | ❌ Eksik | Spec'te var, modül yok (Bot Score / Fingerprint koşulları buna bağlı) |

---

## Karar Tipleri / Aksiyonlar (Actions)

| Aksiyon | Durum |
|---------|-------|
| Allow / Continue | ✅ |
| Block / Return 444 | ✅ |
| Redirect | ✅ |
| Rate Limit | ✅ |
| Cache | ✅ |
| JS Challenge | ✅ |
| Cookie Challenge | ✅ |
| Log / Tag | ✅ |
| Skip Module / Skip Remaining | ✅ |
| Custom Response | ✅ |
| **Captcha** | ❌ Eksik | JS/Cookie challenge var; gerçek CAPTCHA (hCaptcha/Turnstile) yok |

---

## Koşullar (Policy Conditions)

| Koşul | Durum |
|-------|-------|
| Host, Path, Method, Headers, Cookies | ✅ |
| Country, ASN, IP, CIDR | ✅ |
| Trusted Bot | ✅ |
| Rate | ✅ |
| Request Size, Time, Custom Variables | ✅ |
| **Bot Score** | ❌ Eksik (Behavior Analysis'e bağlı) |
| **Fingerprint** | ❌ Eksik (Fingerprinting modülüne bağlı) |

---

## Dashboard / UI Sayfaları

| Sayfa | Durum | Not |
|-------|-------|-----|
| Dashboard | ✅ | Canlı metrikler + Banlı/İzlenen IP kartları |
| Sites | ✅ | CRUD, upstream URL, pipeline özeti |
| Policies | ✅ | Koşul/aksiyon builder ile tam CRUD |
| Rate Limits | ✅ | Site bazlı kural yönetimi |
| Edge Security (Security Modules) | ✅ | ASN, header, burst, GeoIP, custom rules, challenge |
| Managed WAF | ✅ | Coraza mod/paranoia/exclude |
| Pipeline | ✅ | Sürükle-bırak sıralama, aç/kapat |
| Request Trace | ✅ | Canlı istek izleme + açıklanabilirlik |
| Certificates | ✅ | Let's Encrypt / ACME |
| **Modules** (`/modules`) | ❌ Placeholder | Nav'da var, route yok → "Coming soon" |
| **Threat Intelligence** (`/threat-intel`) | ❌ Placeholder | Motor modülü var, özel sayfa yok |
| **Analytics** (`/analytics`) | ❌ Placeholder | Ayrı analitik sayfası yok |
| **Logs** (`/logs`) | ❌ Placeholder | Log görüntüleme sayfası yok |
| **Settings** (`/settings`) | ❌ Placeholder | Ayarlar sayfası yok |

---

## Altyapı & Dağıtım (Infra & Deploy)

| Öğe | Durum | Not |
|-----|-------|-----|
| Docker imajları | ✅ | engine, api, ui, worker, watcher, haproxy |
| Docker Compose | ✅ | Healthcheck + startup ordering |
| HAProxy edge (TLS/L4/stick tables/ban) | ✅ | `deploy/haproxy/*` |
| Redis (sayaçlar) | ✅ | |
| SQLite (dev) / PostgreSQL (prod) | ✅ | |
| Config hot reload | ✅ | `POST /badsector/admin/reload` |
| JWT auth | ✅ | |
| CI (Go test + Docker smoke) | ✅ | `.github/workflows/ci.yml` |
| Sunucu kurulum/güncelleme scriptleri | ✅ | `scripts/install-server.sh`, `update-server.sh` |
| **Helm Chart** | 🟡 İskelet | `deploy/helm/badsector/` (Chart.yaml + values.yaml); tam manifest seti eksik |
| **Kubernetes desteği** | ❌ Gelecek | Spec'te "future" |
| **Lua Plugin sistemi** | 🟡 Kısmen | `plugins/example-block-path/` örneği + CLI `plugin` komutu var; tam plugin loader/registry olgunlaşmamış |

---

## Öncelikli Eksikler (Özet TODO)

1. **UI placeholder sayfalarını doldur**: Modules, Threat Intelligence, Analytics, Logs, Settings.
2. **Edge (HAProxy) drop/429 metriği** → dashboard "Edge'de Engellenen" kartı.
3. **Behavior Analysis** ve **Fingerprinting** modülleri (+ Bot Score / Fingerprint koşulları).
4. **Captcha** aksiyonu (hCaptcha / Cloudflare Turnstile entegrasyonu).
5. **CLI'yi gerçek HTTP çağrılarıyla** tamamla (sites/reload/plugin).
6. **Agent**: config sync + sağlık/metrik raporlama.
7. **Helm chart**'ı üretim için tamamla; Kubernetes manifestleri.
8. **Plugin sistemi**ni birinci sınıf hâle getir (loader, registry, doküman).
