#!/usr/bin/env bash
# Diagnose GeoIP + origin headers on a running BadSector server.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

HOST="${1:-www.koleksi1001resepi.com}"
TEST_IP="${2:-8.8.8.8}"

compose() {
  bash "${ROOT}/scripts/compose.sh" "$@"
}

echo "==> MMDB on host"
ls -lh data/geoip/*.mmdb 2>/dev/null || echo "MISSING: data/geoip/*.mmdb"

echo ""
echo "==> MMDB inside engine"
compose exec -T engine ls -lh /etc/badsector/geoip/ 2>/dev/null || true

echo ""
echo "==> Engine image has geo_lookup + origin_headers"
compose exec -T engine sh -c '
  test -f /usr/local/openresty/badsector/lib/badsector/geo_lookup.lua && echo geo_lookup:OK
  test -f /usr/local/openresty/badsector/lib/badsector/origin_headers.lua && echo origin_headers:OK
  grep -q X-Geo-Status /usr/local/openresty/nginx/conf/nginx.conf && echo nginx_geo_headers:OK
'

echo ""
echo "==> Engine reload"
compose exec -T engine curl -sf -X POST http://127.0.0.1:8080/badsector/admin/reload \
  -H "X-BadSector-Admin-Token: badsector-engine-token"
echo

echo ""
echo "==> Trace (simulated client IP ${TEST_IP})"
curl -skI "https://127.0.0.1/" \
  -H "Host: ${HOST}" \
  -H "X-Forwarded-For: ${TEST_IP}" \
  | grep -iE 'x-badsector-trace|x-geo-status|x-country|x-badsector-edge' || true

echo ""
echo "==> Origin headers (engine -> backend dry run)"
compose exec -T engine curl -sI \
  -H "Host: ${HOST}" \
  -H "X-Forwarded-For: ${TEST_IP}" \
  "http://127.0.0.1:8080/" 2>/dev/null | grep -iE 'x-geo|x-country|x-badsector|x-real-ip' || true

echo ""
echo "PHP tarafinda beklenen anahtarlar:"
echo "  HTTP_X_BADSECTOR_EDGE=1"
echo "  HTTP_X_GEO_STATUS=ok|unavailable|db_missing|disabled"
echo "  HTTP_X_COUNTRY_CODE=TR (status=ok ise)"
