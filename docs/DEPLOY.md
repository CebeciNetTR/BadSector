# GitHub & Sunucu Kurulumu

BadSector'u GitHub'a yükleyip Linux sunucuda Docker ile çalıştırma rehberi.

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
- Ubuntu 22.04+ / Debian 12+
- Root veya sudo
- Portlar: **80**, **443**, **3000** (admin), **9080** (dev edge)

### Yöntem A — clone + script

```bash
sudo apt update && sudo apt install -y git curl

sudo git clone https://github.com/KULLANICI_ADINIZ/BadSector.git /opt/badsector
cd /opt/badsector
sudo cp .env.example .env
sudo nano .env          # secrets — aşağıya bakın
sudo ./scripts/install-server.sh /opt/badsector
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
BADSECTOR_JWT_SECRET=uzun-rastgele-bir-string
BADSECTOR_ADMIN_USER=admin
BADSECTOR_ADMIN_PASSWORD=guclu-sifre

# TLS
BADSECTOR_HAPROXY_CONFIG=live
BADSECTOR_ACME_EMAIL=admin@sizindomain.com
BADSECTOR_ACME_STAGING=false

# GeoIP
MAXMIND_LICENSE_KEY=your_maxmind_key

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

```bash
cd /opt/badsector
sudo ./scripts/update-server.sh
```

---

## 5. Firewall

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3000/tcp   # admin UI — production'da VPN/SSH tunnel önerilir
sudo ufw enable
```

Production'da `:3000` dışarıya açmak yerine SSH tunnel:

```bash
ssh -L 3000:localhost:3000 user@sunucu-ip
# Tarayıcı: http://localhost:3000
```

---

## 6. İlk yapılandırma checklist

| Adım | Nerede |
|------|--------|
| Site oluştur (hostname = domain) | Dashboard → Sites |
| Pipeline modülleri | Pipeline |
| GeoIP MMDB (worker indirir) | `MAXMIND_LICENSE_KEY` + worker log |
| TLS sertifikası | Certificates → Let's Encrypt Al |
| HAProxy TLS reload | `docker compose restart haproxy` |
| Smoke test | `./scripts/smoke-test.sh` |

---

## 7. Sorun giderme

| Sorun | Çözüm |
|-------|--------|
| `git push` auth hatası | GitHub Personal Access Token veya SSH key |
| Docker permission denied | `sudo usermod -aG docker $USER` + logout |
| Port 80 kullanımda | `sudo ss -tlnp \| grep :80` — nginx/apache durdurun |
| GeoIP eksik | Worker log: `docker compose logs worker` |
| Sertifika alınamıyor | DNS, port 80, `BADSECTOR_HAPROXY_CONFIG=live` |

---

## Dosya yapısı (sunucu)

```
/opt/badsector/
├── .env              # secrets (git'te yok)
├── data/
│   ├── geoip/        # MaxMind MMDB (worker indirir)
│   └── certs/        # Let's Encrypt PEM
├── docker-compose.yml
└── scripts/
    ├── install-server.sh
    └── update-server.sh
```
