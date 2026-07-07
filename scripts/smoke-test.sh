#!/usr/bin/env bash
# BadSector smoke test — run after: docker compose up -d --build
set -euo pipefail

API="${BADSECTOR_API_URL:-http://localhost:8080}"
ENGINE="${BADSECTOR_ENGINE_URL:-http://localhost:9080}"
UI="${BADSECTOR_UI_URL:-http://localhost:3000}"
HOST="${BADSECTOR_TEST_HOST:-localhost}"

pass=0
fail=0

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "  OK  $name"
    pass=$((pass + 1))
  else
    echo "  FAIL $name"
    fail=$((fail + 1))
  fi
}

http_ok() {
  local url="$1"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  [[ "$code" == "200" ]]
}

http_ok_host() {
  local url="$1"
  local host="$2"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${host}" "$url")
  [[ "$code" == "200" ]]
}

json_has_sites() {
  curl -sf "${API}/api/v1/sites" | grep -q '"name"'
}

echo "BadSector smoke test"
echo "  API:    $API"
echo "  Engine: $ENGINE (Host: $HOST)"
echo "  UI:     $UI"
echo

check "API health" http_ok "${API}/health"
check "Engine health" http_ok "${ENGINE}/badsector/health"
check "UI responds" http_ok "${UI}/"
check "API lists sites" json_has_sites
check "Engine proxies to backend" http_ok_host "${ENGINE}/" "$HOST"
check "UI proxies API" http_ok "${UI}/api/v1/sites"
check "Dashboard metrics" http_ok "${API}/api/v1/metrics/dashboard"

echo
if [[ "$fail" -eq 0 ]]; then
  echo "All ${pass} checks passed."
  exit 0
fi

echo "${fail} check(s) failed, ${pass} passed."
exit 1
