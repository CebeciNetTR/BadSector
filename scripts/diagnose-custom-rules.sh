#!/usr/bin/env bash
# Diagnose custom rules: DB vs runtime vs live HTTP response.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-trend.koleksi1001resepi.com}"
PATH_TEST="${2:-/wp-wiki/wp-}"
API="${BADSECTOR_API:-http://127.0.0.1:8080/api/v1}"

compose() {
  bash "${ROOT}/scripts/compose.sh" "$@"
}

echo "==> Runtime sites.json (custom_rules for host ${HOST})"
compose exec -T api sh -c "grep -n \"${HOST}\|custom_rules\|\\\"rules\\\"\|\\\"expr\\\"\" /runtime/sites.json | head -40" 2>/dev/null || \
  docker-compose exec -T api sh -c "grep -n \"${HOST}\|custom_rules\|\\\"rules\\\"\|\\\"expr\\\"\" /runtime/sites.json | head -40" 2>/dev/null || true

echo ""
echo "==> Engine recent custom_rules logs"
compose logs engine --tail 40 2>/dev/null | grep -i "custom_rules\|badsector" || true

echo ""
echo "==> Live HTTP test"
curl -sI -H "Host: ${HOST}" "http://127.0.0.1:9080${PATH_TEST}" | grep -iE "HTTP|X-BadSector|Server" || true

echo ""
echo "Tip: Panelden Custom Rules kaydettikten sonra:"
echo "  curl -s ${API}/sites/<SITE_ID>/custom-rules/status"
