#!/usr/bin/env bash
# Update running BadSector from git and rebuild containers.
#
# Usage (on server):
#   cd /opt/badsector && bash scripts/update-server.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

COMPOSE="${ROOT}/scripts/compose.sh"
BRANCH="${BADSECTOR_BRANCH:-main}"

echo "Pulling ${BRANCH}..."
git fetch origin
git checkout "${BRANCH}"
git pull origin "${BRANCH}"

bash "${ROOT}/scripts/setup-dev-data.sh"
bash "${ROOT}/scripts/fix-certs-layout.sh"

"${COMPOSE}" build --no-cache haproxy api worker
"${COMPOSE}" up -d --build

echo "Update complete. Health:"
curl -sf "http://127.0.0.1:8080/health" && echo ""
echo "HAProxy:"
"${COMPOSE}" ps haproxy
"${COMPOSE}" logs haproxy --tail 5
