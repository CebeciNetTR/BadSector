#!/usr/bin/env bash
# Update running BadSector from git and rebuild containers.
#
# Policy: all product changes land in git first; servers only git pull + this script.
#
# Usage (on server):
#   cd /opt/badsector && bash scripts/update-server.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

compose() {
  bash "${ROOT}/scripts/compose.sh" "$@"
}

BRANCH="${BADSECTOR_BRANCH:-main}"

echo "==> Pull ${BRANCH}"
git fetch origin
git checkout "${BRANCH}"
# Sunucuda chmod/sed ile oluşan izlenen dosya farklarını at; .env gitignore'da kalır.
git reset --hard "origin/${BRANCH}"
echo "    $(git log -1 --oneline)"

echo "==> Data dirs + cert layout"
bash "${ROOT}/scripts/setup-dev-data.sh"
bash "${ROOT}/scripts/fix-certs-layout.sh"

echo "==> Rebuild (edge + API + UI)"
compose build --no-cache haproxy engine api worker ui
compose up -d --build

echo "==> Health"
sleep 3
curl -sf "http://127.0.0.1:8080/health" && echo "api: ok"
curl -sf "http://127.0.0.1:9080/badsector/health" 2>/dev/null && echo "edge: ok" || true

echo "==> HAProxy"
compose ps haproxy
compose logs haproxy --tail 8

if compose ps haproxy 2>/dev/null | grep -qE 'Restarting|Exited'; then
  echo ""
  echo "ERROR: HAProxy is not healthy."
  echo "  bash scripts/fix-certs-layout.sh"
  echo "  ls -la data/certs/haproxy/"
  echo "  compose logs haproxy --tail 30"
  exit 1
fi

echo ""
echo "Update complete."
