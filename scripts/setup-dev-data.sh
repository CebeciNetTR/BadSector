#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "${ROOT}/data/geoip"
mkdir -p "${ROOT}/data/certs"
mkdir -p "${ROOT}/runtime"

echo "Dev data directories ready:"
echo "  ${ROOT}/data/geoip   (GeoLite2-Country.mmdb, GeoLite2-ASN.mmdb)"
echo "  ${ROOT}/runtime      (generated sites.json for local API)"

if [[ -f "${ROOT}/data/geoip/GeoLite2-Country.mmdb" ]]; then
  echo "GeoIP Country database: present"
else
  echo "GeoIP Country database: missing"
fi
if [[ -f "${ROOT}/data/geoip/GeoLite2-ASN.mmdb" ]]; then
  echo "GeoIP ASN database: present"
else
  echo "GeoIP ASN database: missing"
fi
if [[ ! -f "${ROOT}/data/geoip/GeoLite2-Country.mmdb" ]] || [[ ! -f "${ROOT}/data/geoip/GeoLite2-ASN.mmdb" ]]; then
  echo "  export MAXMIND_LICENSE_KEY=... && ./scripts/download-geoip.sh"
fi

echo
echo "Start stack: docker compose up -d --build"
