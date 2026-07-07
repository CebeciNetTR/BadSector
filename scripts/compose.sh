#!/usr/bin/env bash
# Use docker-compose (v1) or docker compose (v2 plugin), whichever exists.
set -euo pipefail

if command -v docker-compose >/dev/null 2>&1; then
  exec docker-compose "$@"
fi
if docker compose version >/dev/null 2>&1; then
  exec docker compose "$@"
fi
echo "Neither docker-compose nor docker compose found." >&2
exit 1
