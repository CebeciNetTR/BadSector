# TLS Certificates (Let's Encrypt)

BadSector obtains and renews TLS certificates via **ACME HTTP-01** (Let's Encrypt).

## Architecture

```
Let's Encrypt  ←→  API/Worker (lego)  →  Redis (challenge tokens)
                                              ↓
Port 80  →  HAProxy  →  Engine  →  /.well-known/acme-challenge/{token}
Port 443 →  HAProxy (TLS)  →  Engine pipeline  →  Backend
```

Certificate files are written to `BADSECTOR_CERTS_PATH` (default `./data/certs`):

| File | Purpose |
|------|---------|
| `example.com.pem` | HAProxy combined cert+key |
| `example.com.crt` | Certificate only |
| `example.com.key` | Private key |

## Setup (live server)

1. DNS A/AAAA record pointing to your server
2. `.env`:

```bash
BADSECTOR_HAPROXY_CONFIG=live
BADSECTOR_ACME_EMAIL=admin@yourdomain.com
BADSECTOR_CERTS_PATH=./data/certs
# Optional staging test first:
# BADSECTOR_ACME_STAGING=true
```

3. Start stack:

```bash
mkdir -p data/certs
docker compose up -d --build
```

4. Dashboard → **Certificates** → select site → enter domain → **Let's Encrypt Al**

5. After successful issue:

```bash
docker compose restart haproxy
```

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/certificates?site_id=` | List certificates |
| GET | `/sites/:id/certificates` | List for site |
| POST | `/sites/:id/certificates` | Create `{domain, email?, auto_renew?, issue?}` |
| POST | `/certificates/:id/issue` | Obtain certificate |
| POST | `/certificates/:id/renew` | Renew certificate |
| DELETE | `/certificates/:id` | Delete record + files |

## Auto renewal

Worker checks every `BADSECTOR_CERT_RENEW_INTERVAL` (default 6h) and renews certs expiring within 30 days.

## Requirements

- Port **80** must be reachable from the internet (HTTP-01)
- Site **hostnames** must include the certificate domain
- For HTTPS traffic, use `BADSECTOR_HAPROXY_CONFIG=live` and open port **443**

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Challenge 404 | Engine ACME route; check Redis connectivity |
| Connection refused on :80 | `BADSECTOR_HAPROXY_CONFIG=live`, firewall |
| Rate limit | Use `BADSECTOR_ACME_STAGING=true` for tests |
| HAProxy no TLS | Restart haproxy after cert files appear in `data/certs/` |
