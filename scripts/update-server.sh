#!/usr/bin/env bash
# Update running BadSector from git and rebuild containers.
#
# Usage (on server):
#   cd /opt/badsector && ./scripts/update-server.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

BRANCH="${BADSECTOR_BRANCH:-main}"

echo "Pulling ${BRANCH}..."
git fetch origin
git checkout "${BRANCH}"
git pull origin "${BRANCH}"

./scripts/setup-dev-data.sh
docker compose up -d --build

echo "Update complete. Health:"
curl -sf "http://127.0.0.1:8080/health" && echo ""
