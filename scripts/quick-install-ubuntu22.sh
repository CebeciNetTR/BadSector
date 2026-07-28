#!/usr/bin/env bash
# BadSector — Ubuntu 22.04 hizli kurulum (Docker Compose)
#
# Yeni VPS (root):
#   apt update && apt install -y git curl
#   git clone https://github.com/CebeciNetTR/BadSector.git /opt/badsector
#   cd /opt/badsector
#   sudo bash scripts/quick-install-ubuntu22.sh
#
# Tek satir (repo public + raw script):
#   curl -fsSL https://raw.githubusercontent.com/CebeciNetTR/BadSector/main/scripts/quick-install-ubuntu22.sh \
#     | sudo BADSECTOR_REPO=https://github.com/CebeciNetTR/BadSector.git bash
#
# Ortam degiskenleri (opsiyonel):
#   BADSECTOR_REPO          git clone URL (klasor bossa)
#   BADSECTOR_INSTALL_DIR   varsayilan /opt/badsector
#   BADSECTOR_BRANCH        varsayilan main
#   BADSECTOR_TRUSTED_IPS   yonetim IP (virgulle)
#   MAXMIND_LICENSE_KEY     GeoLite2 indirme
#   BADSECTOR_ACME_EMAIL    Let's Encrypt
#   BADSECTOR_ADMIN_PASSWORD panel sifresi (bos = rastgele uretilir)

set -euo pipefail

INSTALL_DIR="${BADSECTOR_INSTALL_DIR:-/opt/badsector}"
REPO="${BADSECTOR_REPO:-}"
BRANCH="${BADSECTOR_BRANCH:-main}"
SKIP_DOCKER=false
SKIP_CLONE=false
SKIP_BUILD=false

usage() {
  sed -n '2,22p' "$0"
  echo ""
  echo "Options:"
  echo "  --dir PATH       Kurulum dizini (default: /opt/badsector)"
  echo "  --repo URL       git clone (dizin yoksa)"
  echo "  --branch NAME    git branch (default: main)"
  echo "  --skip-docker    Docker kurma (zaten yuklu)"
  echo "  --skip-clone     Mevcut dizini kullan (git pull yok)"
  echo "  --skip-build     docker compose up atla"
  echo "  -h, --help       Bu yardim"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --skip-docker) SKIP_DOCKER=true; shift ;;
    --skip-clone) SKIP_CLONE=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Bilinmeyen arguman: $1" >&2; usage; exit 1 ;;
  esac
done

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { echo "HATA: $*" >&2; exit 1; }

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "root olarak calistirin: sudo bash $0"
}

check_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    log "OS: ${PRETTY_NAME:-unknown}"
    if [[ "${ID:-}" != "ubuntu" ]] || [[ "${VERSION_ID:-}" != "22.04" ]]; then
      echo "UYARI: Ubuntu 22.04 icin test edildi; devam ediliyor..." >&2
    fi
  fi
}

install_packages() {
  log "Sistem paketleri..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq \
    ca-certificates curl git ipset iptables openssl jq \
    >/dev/null
}

install_sysctl() {
  local f=/etc/sysctl.d/99-badsector.conf
  if [[ -f "$f" ]]; then
    log "sysctl zaten var: $f"
    return 0
  fi
  log "sysctl (edge flood) ayarlari..."
  cat >"$f" <<'EOF'
# BadSector edge — OVH / yuksek baglanti
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
fs.file-max = 2097152
EOF
  sysctl --system >/dev/null 2>&1 || sysctl -p "$f" >/dev/null 2>&1 || true
}

install_docker() {
  if $SKIP_DOCKER; then
    log "Docker kurulumu atlandi (--skip-docker)"
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker zaten yuklu: $(docker --version)"
    return 0
  fi
  log "Docker kuruluyor (get.docker.com)..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
}

ensure_repo() {
  if $SKIP_CLONE; then
    [[ -f "${INSTALL_DIR}/docker-compose.yml" ]] || die "docker-compose.yml yok: ${INSTALL_DIR}"
    log "Mevcut dizin: ${INSTALL_DIR}"
    return 0
  fi

  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log "Git repo mevcut, guncelleniyor: ${INSTALL_DIR}"
    git -C "${INSTALL_DIR}" fetch origin "${BRANCH}" --depth 1 2>/dev/null || true
    git -C "${INSTALL_DIR}" checkout "${BRANCH}" 2>/dev/null || true
    git -C "${INSTALL_DIR}" pull --ff-only origin "${BRANCH}" 2>/dev/null || true
    return 0
  fi

  if [[ -n "$REPO" ]]; then
    log "Clone: ${REPO} -> ${INSTALL_DIR}"
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    git clone --branch "${BRANCH}" --depth 1 "${REPO}" "${INSTALL_DIR}"
    return 0
  fi

  if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
    log "Dizin hazir (clone yok): ${INSTALL_DIR}"
    return 0
  fi

  die "Repo yok. Ornek:\n  git clone https://github.com/CebeciNetTR/BadSector.git ${INSTALL_DIR}\n  veya: BADSECTOR_REPO=... bash $0"
}

fix_scripts() {
  local root="$1"
  for f in "${root}"/scripts/*.sh; do
    [[ -f "$f" ]] || continue
    sed -i 's/\r$//' "$f" 2>/dev/null || true
    chmod +x "$f" 2>/dev/null || true
  done
}

rand_hex() {
  openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 64
}

write_env_if_missing() {
  local root="$1"
  local env_file="${root}/.env"
  if [[ -f "$env_file" ]]; then
    log ".env mevcut — dokunulmadi"
    return 0
  fi

  log ".env olusturuluyor (production varsayilanlari)..."
  local jwt secret admin_pw acme trusted maxmind
  jwt="$(rand_hex)"
  secret="$(rand_hex)"
  admin_pw="${BADSECTOR_ADMIN_PASSWORD:-$(openssl rand -base64 18 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 16)}"
  acme="${BADSECTOR_ACME_EMAIL:-}"
  trusted="${BADSECTOR_TRUSTED_IPS:-}"
  maxmind="${MAXMIND_LICENSE_KEY:-}"

  cp "${root}/.env.example" "$env_file"

  # Production edge
  if grep -q '^BADSECTOR_HAPROXY_CONFIG=' "$env_file"; then
    sed -i 's/^BADSECTOR_HAPROXY_CONFIG=.*/BADSECTOR_HAPROXY_CONFIG=live/' "$env_file"
  else
    echo "BADSECTOR_HAPROXY_CONFIG=live" >>"$env_file"
  fi

  sed -i "s/^BADSECTOR_JWT_SECRET=.*/BADSECTOR_JWT_SECRET=${jwt}/" "$env_file"
  sed -i "s/^BADSECTOR_CHALLENGE_SECRET=.*/BADSECTOR_CHALLENGE_SECRET=${secret}/" "$env_file"
  sed -i "s/^BADSECTOR_AUTH_DISABLED=.*/BADSECTOR_AUTH_DISABLED=false/" "$env_file"
  sed -i "s/^BADSECTOR_ADMIN_PASSWORD=.*/BADSECTOR_ADMIN_PASSWORD=${admin_pw}/" "$env_file"

  if [[ -n "$trusted" ]]; then
    if grep -q '^BADSECTOR_TRUSTED_IPS=' "$env_file"; then
      sed -i "s|^BADSECTOR_TRUSTED_IPS=.*|BADSECTOR_TRUSTED_IPS=${trusted}|" "$env_file"
    else
      echo "BADSECTOR_TRUSTED_IPS=${trusted}" >>"$env_file"
    fi
  fi

  if [[ -n "$acme" ]]; then
    sed -i "s/^BADSECTOR_ACME_EMAIL=.*/BADSECTOR_ACME_EMAIL=${acme}/" "$env_file"
  fi

  if [[ -n "$maxmind" ]]; then
    sed -i "s/^MAXMIND_LICENSE_KEY=.*/MAXMIND_LICENSE_KEY=${maxmind}/" "$env_file"
  fi

  chmod 600 "$env_file"
  echo ""
  echo "=========================================="
  echo "  Panel giris ( .env icinde sakli )"
  echo "  Kullanici : admin (BADSECTOR_ADMIN_USER)"
  echo "  Sifre     : ${admin_pw}"
  echo "=========================================="
  echo ""
}

download_geoip_optional() {
  local root="$1"
  if [[ -f "${root}/data/geoip/GeoLite2-Country.mmdb" ]] \
    && [[ -f "${root}/data/geoip/GeoLite2-ASN.mmdb" ]]; then
    log "GeoIP MMDB mevcut"
    return 0
  fi
  if [[ -z "${MAXMIND_LICENSE_KEY:-}" ]]; then
    # .env'den oku
    if [[ -f "${root}/.env" ]]; then
      # shellcheck source=/dev/null
      maxmind_line=$(grep -E '^MAXMIND_LICENSE_KEY=' "${root}/.env" 2>/dev/null | tail -1 || true)
      MAXMIND_LICENSE_KEY="${maxmind_line#MAXMIND_LICENSE_KEY=}"
    fi
  fi
  if [[ -z "${MAXMIND_LICENSE_KEY:-}" ]]; then
    log "GeoIP atlandi — MAXMIND_LICENSE_KEY yok (.env sonra ekleyin)"
    return 0
  fi
  log "GeoLite2 indiriliyor..."
  export MAXMIND_LICENSE_KEY
  bash "${root}/scripts/download-geoip.sh" || log "GeoIP indirme basarisiz (sonra tekrar deneyin)"
}

start_stack() {
  local root="$1"
  if $SKIP_BUILD; then
    log "docker compose atlandi (--skip-build)"
    return 0
  fi
  log "Docker Compose build + up (ilk sefer 5-15 dk surebilir)..."
  cd "$root"
  bash "${root}/scripts/compose.sh" up -d --build
}

print_summary() {
  local root="$1"
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  ip="${ip:-SUNUCU_IP}"

  echo ""
  echo "=============================================="
  echo "  BadSector kurulum tamamlandi"
  echo "=============================================="
  echo "  Dizin     : ${root}"
  echo "  Panel     : http://${ip}:3000"
  echo "  API health: http://127.0.0.1:8080/health (localhost)"
  echo "  Edge HTTPS: https://${ip}:443 (sertifika / domain gerekir)"
  echo ""
  echo "  Sonraki adimlar:"
  echo "    1. nano ${root}/.env"
  echo "       BADSECTOR_TRUSTED_IPS=KENDI_IP"
  echo "       BADSECTOR_ACME_EMAIL=admin@domain.com"
  echo "       MAXMIND_LICENSE_KEY=..."
  echo "    2. GeoIP:  bash ${root}/scripts/download-geoip.sh"
  echo "    3. .env degistiysen: cd ${root} && bash scripts/compose.sh up -d"
  echo "    4. Log:    bash ${root}/scripts/compose.sh logs -f"
  echo "    5. Guncelleme: bash ${root}/scripts/update-server.sh"
  echo ""
  echo "  Firewall: 80/443 acik; 3000/8080/6379 disariya KAPALI tutun."
  echo "  Watcher ipset icin KVM/VPS root gerekir (compose privileged)."
  echo "=============================================="
}

main() {
  require_root
  check_os
  install_packages
  install_sysctl
  install_docker
  ensure_repo
  fix_scripts "${INSTALL_DIR}"
  cd "${INSTALL_DIR}"
  write_env_if_missing "${INSTALL_DIR}"
  bash "${INSTALL_DIR}/scripts/setup-dev-data.sh"
  bash "${INSTALL_DIR}/scripts/fix-certs-layout.sh"
  download_geoip_optional "${INSTALL_DIR}"
  start_stack "${INSTALL_DIR}"
  print_summary "${INSTALL_DIR}"
}

main "$@"
