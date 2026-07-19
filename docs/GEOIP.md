# GeoIP & ASN (MaxMind)

BadSector uses **GeoLite2-Country** and **GeoLite2-ASN** MMDB files for the `geoip` and `asn` pipeline modules.

## Setup

1. Create a free MaxMind account: https://www.maxmind.com/en/geolite2/signup
2. Generate a license key
3. Set environment variable:

```bash
export MAXMIND_LICENSE_KEY=your_key_here
```

### Docker Compose

```yaml
# .env or shell
MAXMIND_LICENSE_KEY=your_key_here
```

The **worker** downloads databases on startup and every 24h (`BADSECTOR_GEOIP_SYNC_INTERVAL`).

Shared volume: `./data/geoip` → engine `/etc/badsector/geoip`

### Manual download

```bash
./scripts/download-geoip.sh
docker compose restart engine worker
```

## Files

| File | Module |
|------|--------|
| `GeoLite2-Country.mmdb` | `geoip` — country/city |
| `GeoLite2-ASN.mmdb` | `asn` — autonomous system number |

## GeoIP module

Config via **Edge Security → GeoIP** or `GET/PUT /api/v1/sites/:id/geoip`.

| Field | Description |
|-------|-------------|
| `database_path` | Path to Country MMDB |
| `block_countries` | ISO codes to block (e.g. `CN`, `RU`) |
| `allow_countries` | With `allow_only: true` |
| `allow_only` | Only listed countries pass |
| `fail_open` | Continue if lookup fails (**production'da true kalsın**) |
| `use_header_fallback` | Use `CF-IPCountry` / `X-Country-Code` if MMDB missing |
| `deny_action` | Reddetmede ne yapılsın: `block` (403), `drop` (444), `challenge` (JS PoW). Varsayılan `block`. |
| `ban_threshold` | Yalnız `challenge`: 60 sn içinde bu kadar çözümsüz **belge** isteği → Redis ban (varsayılan **5**) |
| `ban_ttl` | Ban süresi saniye (varsayılan 86400). Redis değeri: `geoip_challenge` |
| `pass_ttl` | `bs_pass` süresi (varsayılan 3600) |

Sets `ctx.enrich.geo` and `ctx.vars.country` for policy conditions.

### Production notes (edge = BadSector)

- **`allow_only` + `TR`**: Yabancı trafik `deny_action` ile kesilir (varsayılan 403). `trusted_bots` pipeline'da **önce** olduğu için doğrulanmış Googlebot/Bingbot muaf kalır.
- **`deny_action: challenge`**: Allow-list dışı ülkelere JS PoW; TR kullanıcı challenge görmez. Ayrı `js_challenge` modülü gerekmez. Fail sayacı favicon/statik asset'te artmaz; eşik aşılınca `bs:ban:<ip>=geoip_challenge`.
- **`drop`**: Bağlantıyı sessiz kapatır (ban sayacı yok).
- **`fail_open: true`**: MMDB bir an eksikken tüm siteyi kilitlemez.
- **`use_header_fallback`**: Siz Cloudflare arkasında değilseniz **kapatın**. Aksi halde istemci sahte `CF-IPCountry: TR` ile (MMDB çözülemediğinde) allow-list'i atlayabilir.
- GeoIP **challenge muafiyeti değildir** — TR kullanıcı attack mode / js_challenge açıksa yine challenge görür. Challenge'ı kapatmak veya attack mode'u kapalı tutmak ayrı ayardır.
- Performans: MMDB memory-map; istek başına mikrosaniye civarı — 8GB kutuda pahalı değil, flood'da pahalı modüllerden önce keser.

## ASN module

Uses `GeoLite2-ASN.mmdb` automatically when present. Fallback: `ip_map` overrides.

| Field | Description |
|-------|-------------|
| `database_path` | Path to ASN MMDB |
| `block_asns` / `allow_asns` | ASN number lists |
| `allow_only` | Restrict to allow list |
| `ip_map` | Manual IP → ASN overrides |

Sets `ctx.enrich.asn` and `ctx.vars.asn`.

## API status

```bash
curl http://localhost:8080/api/v1/geoip/status
```

```json
{
  "country_path": "/data/geoip/GeoLite2-Country.mmdb",
  "asn_path": "/data/geoip/GeoLite2-ASN.mmdb",
  "country_ok": true,
  "asn_ok": true,
  "last_sync": "2026-07-07T00:15:00Z"
}
```

## Policy integration

GeoIP must run **before** `policies` in the pipeline:

```json
{ "type": "country", "operator": "not_in", "value": ["TR", "DE"] }
```

## Pipeline order

```
… → ip_reputation → geoip → asn → policies → …
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `country_ok: false` | Set `MAXMIND_LICENSE_KEY`, check worker logs |
| Country always unknown | Ensure geoip module enabled in pipeline |
| ASN unknown | Wait for ASN MMDB download; check `asn_ok` in status |
| Engine not picking up new DB | Worker triggers reload after sync; or `POST /api/v1/runtime/reload` |
