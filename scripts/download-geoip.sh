#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${MAXMIND_LICENSE_KEY:-}"

load_key_from_env_file() {
  local env_file="$1"
  local line raw
  [[ -f "$env_file" ]] || return 1
  line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?MAXMIND_LICENSE_KEY=' "$env_file" 2>/dev/null | tail -1 || true)
  [[ -n "$line" ]] || return 1
  raw="${line#*=}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  raw="${raw%$'\r'}"
  # tirnak kaldir
  raw="${raw#\"}"; raw="${raw%\"}"
  raw="${raw#\'}"; raw="${raw%\'}"
  [[ -n "$raw" ]] || return 1
  KEY="$raw"
  return 0
}

if [[ -z "${KEY}" ]]; then
  load_key_from_env_file "${ROOT}/.env" || true
fi
if [[ -z "${KEY}" && -f "${ROOT}/data/restore/secrets.env" ]]; then
  load_key_from_env_file "${ROOT}/data/restore/secrets.env" || true
fi

if [[ -z "${KEY}" ]]; then
  echo "MAXMIND_LICENSE_KEY is required."
  echo "Free key: https://www.maxmind.com/en/geolite2/signup"
  echo ""
  echo "Kontrol:"
  echo "  grep -i maxmind ${ROOT}/.env"
  echo "  export MAXMIND_LICENSE_KEY='...' && bash $0"
  exit 1
fi

mkdir -p "${ROOT}/data/geoip"

download() {
  local edition="$1"
  local out="${ROOT}/data/geoip/${edition}.mmdb"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN

  local url="https://download.maxmind.com/app/geoip_download?edition_id=${edition}&license_key=${KEY}&suffix=tar.gz"
  echo "Downloading ${edition}..."
  curl -fsSL "${url}" -o "${tmp}/geo.tgz"
  tar -xzf "${tmp}/geo.tgz" -C "${tmp}"
  local mmdb
  mmdb="$(find "${tmp}" -name "${edition}.mmdb" | head -1)"
  cp "${mmdb}" "${out}"
  echo "Saved ${out}"
}

download "GeoLite2-Country"
download "GeoLite2-ASN"
date -u +%Y-%m-%dT%H:%M:%SZ > "${ROOT}/data/geoip/.last_sync"
echo "Done. Restart engine: docker compose restart engine worker"
