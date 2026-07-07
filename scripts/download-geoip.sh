#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${MAXMIND_LICENSE_KEY:-}"

if [[ -z "${KEY}" ]]; then
  echo "MAXMIND_LICENSE_KEY is required."
  echo "Free key: https://www.maxmind.com/en/geolite2/signup"
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
