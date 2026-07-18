# GitHub & Sunucu Kurulumu

BadSector güncellemeleri **yalnızca git üzerinden** dağıtılır:

1. **Geliştirme** — değişiklikler repoda (Cursor / local)
2. **GitHub** — `git push origin main`
3. **Sunucu** — `git pull` + `bash scripts/update-server.sh`

Sunucuda elle dosya düzenleme veya `docker-compose` build argümanlarını kalıcı değiştirme yapmayın; `.env` hariç tüm ürün kodu repodan gelmelidir.

---

## 1. GitHub'a yükleme (ilk kez)

### Windows'ta Git kurulumu

1. [Git for Windows](https://git-scm.com/download/win) indirin ve kurun
2. **Git Bash** açın, proje klasörüne gidin:

```bash
cd /c/Users/miroglu/Desktop/BadSector
```

### Repo oluşturma ve push

GitHub'da `BadSector` reposunu oluşturduysanız (README/license eklemeden boş repo önerilir):

```bash
git init
git add .
git commit -m "Initial commit: BadSector edge security platform"
git branch -M main
git remote add origin https://github.com/KULLANICI_ADINIZ/BadSector.git
git push -u origin main
```

`KULLANICI_ADINIZ` yerine kendi GitHub kullanıcı adınızı yazın.

> **Önemli:** `.env` dosyası `.gitignore` içinde — commit edilmez. Sadece `.env.example` gider.

### SSH ile push (opsiyonel)

```bash
git remote set-url origin git@github.com:KULLANICI_ADINIZ/BadSector.git
git push -u origin main
```

---

## 2. Sunucuya kurulum (tek komut)

Sunucu gereksinimleri:
- Ubuntu 22.04+ / Debian 12+ (**KVM** önerilir — watcher iptables/ipset kullanır)
- Root veya sudo
- **Hedef (OVH edge):** 8 vCPU / 24 GB RAM / yüksek bant genişliği — compose + `haproxy-live` buna göre ayarlı
- Minimum: 4+ vCPU / 8 GB RAM (düşük-orta; büyük botnet için üst katman gerekir)
- Portlar: **80**, **443** (public); admin UI (`BADSECTOR_UI_PORT`, varsayılan **3000**); **9080** (dev edge)
- Redis/Postgres/API compose'ta yalnızca **127.0.0.1** üzerinde dinler (internete açmayın)

### OVH / 8c·24GB — host sysctl (önerilen)

```bash
cat <<'EOF' | sudo tee /etc/sysctl.d/99-badsector.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
fs.file-max = 2097152
EOF
sudo sysctl --system
```

Compose varsayılanları (24GB): Redis `maxmemory 2gb`, Postgres `shared_buffers=1GB`, HAProxy `nbthread 8` / `maxconn 100000`, watcher `BAN_TTL=7200`.

### Yöntem A — clone + script

```bash
sudo apt update && sudo apt install -y git curl

sudo git clone https://github.com/KULLANICI_ADINIZ/BadSector.git /opt/badsector
cd /opt/badsector
sudo cp .env.example .env
sudo nano .env          # secrets — aşağıya bakın
sudo ./scripts/install-server.sh /opt/badsector
# veya (sh kullanmayın):
bash scripts/install-server.sh /opt/badsector
```

### Yöntem B — curl ile (repo public ise)

```bash
export BADSECTOR_REPO=https://github.com/KULLANICI_ADINIZ/BadSector.git
curl -fsSL https://raw.githubusercontent.com/KULLANICI_ADINIZ/BadSector/main/scripts/install-server.sh | sudo bash
```

---

## 3. Sunucu `.env` ayarları (production)

`/opt/badsector/.env` örneği:

```bash
# Auth — production'da mutlaka açın
BADSECTOR_AUTH_DISABLED=false
BADSECTOR_JWT_SECRET=$(openssl rand -hex 32)   # .env'e gerçek hex yazın; $(...) literal olmasın
BADSECTOR_ADMIN_USER=admin
BADSECTOR_ADMIN_PASSWORD=guclu-sifre

# PoW challenge HMAC — üretimde mutlaka güçlü rastgele
BADSECTOR_CHALLENGE_SECRET=$(openssl rand -hex 32)

# TLS
BADSECTOR_HAPROXY_CONFIG=live
BADSECTOR_ACME_EMAIL=admin@sizindomain.com
BADSECTOR_ACME_STAGING=false

# GeoIP
MAXMIND_LICENSE_KEY=your_maxmind_key

# Admin UI host portu (opsiyonel; varsayılan 3000)
# BADSECTOR_UI_PORT=8443

# Opsiyonel
BADSECTOR_DEFAULT_BACKEND_URL=http://backend:80
```

Sonra:

```bash
cd /opt/badsector
docker compose up -d --build
```

---

## 4. Güncelleme (sunucuda)

**Normal (hızlı — önerilen):**

```bash
cd /opt/badsector
bash scripts/update-server.sh
```

- Git: `fetch` + **fast-forward merge** (saniyeler). `reset --hard` yalnızca sunucuda izlenen dosyada yerel değişiklik varsa otomatik devreye girer.
- Docker: **cache kullanır**, yalnızca değişen servisleri rebuild eder (`engine/` → engine+haproxy, `ui/` → ui, vb.).

**Tam rebuild (yavaş — Dockerfile / bağımlılık değişince):**

```bash
bash scripts/update-server.sh --full
```

**Zorunlu hard reset (sunucuda tracked dosya oynandıysa):**

```bash
bash scripts/update-server.sh --hard-reset
```

**Tek servis:**

```bash
bash scripts/update-server.sh --services engine,api
```

Manuel güncelleme (eski, yavaş yol — gerek yok):

```bash
cd /opt/badsector
git pull origin main
bash scripts/setup-dev-data.sh
bash scripts/fix-certs-layout.sh
docker-compose build haproxy engine api worker ui
docker-compose up -d --build
docker-compose ps
```

Windows (push):

```bash
cd BadSector
git add -A
git status
git commit -m "açıklayıcı mesaj"
git push origin main
```

> Sunucunuzda `docker-compose` (tireli) kullanın. Repo `scripts/compose.sh` ile ikisini de destekler.

### HAProxy restart döngüsü (acme-*.json)

`data/certs/` kökünde `acme-*.json` varsa HAProxy çöker. Düzeltme repoda:

- ACME account → `data/certs/acme/` (HAProxy okumaz)
- `scripts/fix-certs-layout.sh` eski JSON’ları taşır, gerekirse `temp.pem` oluşturur

```bash
bash scripts/fix-certs-layout.sh
docker-compose restart haproxy
```

---

## 5. Firewall ve port sertleştirme

Compose zaten Redis (`6379`), Postgres (`5432`), API (`8080`) için **127.0.0.1** bind kullanır.
Public olması gerekenler: **80**, **443** (ve isteğe bağlı admin UI portu).

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# Admin UI — mümkünse dışarı açmayın; SSH tunnel kullanın
# sudo ufw allow 3000/tcp
sudo ufw enable
```

Admin UI'ye tunnel ile:

```bash
ssh -L 3000:localhost:3000 user@sunucu-ip
# Tarayıcı: http://localhost:3000
```

`BADSECTOR_UI_PORT` değiştirdiyseniz tunnel hedef portunu ona göre ayarlayın.

> [!WARNING]
> Docker publish, `ufw` kurallarını bypass edebilir. Redis/Postgres'in `0.0.0.0`'da
> olmadığını doğrulayın: `ss -tlnp | grep -E ':6379|:5432|:8080'` → yalnızca `127.0.0.1`.

### Watcher / SSH kilidi

Watcher ban'ı host `iptables` + `ipset bs_banned` yazar — **SSH dahil tüm portlar** düşer.
Kendinizi kilitlerseniz: farklı IP/VPN, sağlayıcı KVM/reboot, sonra:

```bash
# Tum ban'lari bosalt (Redis + ipset + hit sayaci)
sudo ./scripts/clear-bans.sh

# veya manuel
sudo ipset flush bs_banned
sudo iptables -D INPUT -m set --match-set bs_banned src -j DROP 2>/dev/null
cd /opt/badsector && docker compose stop watcher   # geçici
```

**Trusted IP:** `.env` içinde `BADSECTOR_TRUSTED_IPS=x.x.x.x` — iptables ACCEPT, watcher asla banlamaz, engine GeoIP/challenge/ban muaf, HAProxy hit saymaz. Boş bırakılırsa kimse muaf değildir.

---

## 6. İlk yapılandırma checklist

| Adım | Nerede |
|------|--------|
| Site oluştur (hostname = domain, typo yok) | Dashboard → Sites |
| Pipeline — tikler kaydedilir (Enabled DB kolonu) | Pipeline |
| GeoIP allow-list / block | Edge Security → GeoIP; `fail_open=true` kalsın |
| Client IP (spoof) | `.env` → `BADSECTOR_CLOUDFLARE=false` (edge) / `true` (CF arkası). HAProxy + engine birlikte |
| Header fallback | Edge'de GeoIP `CF-IPCountry` fallback'i kapatın |
| GeoIP MMDB | `MAXMIND_LICENSE_KEY` + worker log |
| JS challenge eşiği | Challenges → `ban_threshold` (varsayılan 5) |
| TLS sertifikası | Certificates → Let's Encrypt Al |
| HAProxy TLS reload | `docker compose restart haproxy` |
| Smoke test | `./scripts/smoke-test.sh` |

**TR-odaklı site önerisi:** GeoIP `allow_only` + `TR`; `trusted_bots` açık; attack mode normalde kapalı (acil durumda aç).

---

## 7. Sorun giderme

| Sorun | Çözüm |
|-------|--------|
| `command not found` (install-server.sh) | `bash scripts/install-server.sh` — `sh` değil; CRLF fix: `sed -i 's/\r$//' scripts/*.sh` |
| `Illegal option -o pipefail` | `sh` yerine `bash scripts/install-server.sh` kullanın |
| Docker build: `missing go.sum` / `runtime` | `.gitignore` `runtime/` satırı Go paketini engelliyordu — `git pull` sonrası `internal/runtime/generator.go` olmalı |
| `git push` auth hatası | GitHub Personal Access Token veya SSH key |
| Docker permission denied | `sudo usermod -aG docker $USER` + logout |
| Port 80 kullanımda | `sudo ss -tlnp \| grep :80` — nginx/apache durdurun |
| GeoIP eksik | Worker log: `docker compose logs worker` |
| Sertifika alınamıyor | DNS, port 80, `BADSECTOR_HAPROXY_CONFIG=live`, `bash scripts/fix-certs-layout.sh` |
| HAProxy Restarting | `bash scripts/fix-certs-layout.sh`; geçersiz `data/certs/haproxy/*.pem` silinir/yeniden oluşturulur |
| Redis/API yok / UI gelmiyor | `docker compose ps` — restart policy; `docker compose up -d` |
| Pipeline tikleri geri aktif oluyor | Eski bug (GORM); güncel API'de düzeldi — `update-server.sh --services api,ui` |
| JS challenge ile yanlış ban (favicon) | Güncel engine: asset muaf + eşik 5; ban aç: `redis-cli del bs:ban:IP` |
| ERR_TOO_MANY_REDIRECTS | Origin force-HTTPS + BadSector HTTP proxy; backend URL kendi domain olmasın; `X-Forwarded-Proto` |
| SSH yok, site de yok | Muhtemel ipset ban — KVM/reboot veya başka IP; bkz. §5 Watcher |

---

## Dosya yapısı (sunucu)

```
/opt/badsector/
├── .env              # secrets (git'te yok)
├── data/
│   ├── geoip/        # MaxMind MMDB (worker indirir)
│   ├── challenge/    # template.html — ortak JS challenge (git'te YOK)
│   └── certs/
│       ├── haproxy/  # PEM files for HAProxy (:443)
│       ├── private/  # split crt/key
│       └── acme/     # ACME account JSON
├── docker-compose.yml
└── scripts/
    ├── install-server.sh
    └── update-server.sh
```
