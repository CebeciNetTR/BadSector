#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "${ROOT}/data/geoip"
mkdir -p "${ROOT}/data/bots"
mkdir -p "${ROOT}/data/certs/haproxy"
mkdir -p "${ROOT}/data/certs/acme"
mkdir -p "${ROOT}/data/certs/private"
mkdir -p "${ROOT}/data/haproxy"
mkdir -p "${ROOT}/runtime"

if [[ ! -f "${ROOT}/data/haproxy/site-ratelimit.map" ]]; then
  cp "${ROOT}/deploy/haproxy/maps/site-ratelimit.map" "${ROOT}/data/haproxy/site-ratelimit.map"
  echo "Created data/haproxy/site-ratelimit.map (default template)"
fi

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
