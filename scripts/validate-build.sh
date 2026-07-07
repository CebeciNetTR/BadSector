#!/usr/bin/env bash
# Pre-deploy build check — run from repo root (requires Docker).
# Usage: bash scripts/validate-build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0

run_step() {
  local name="$1"
  shift
  echo ""
  echo "=== ${name} ==="
  if "$@"; then
    echo "OK: ${name}"
  else
    echo "FAIL: ${name}" >&2
    fail=1
  fi
}

go_build() {
  docker run --rm -v "${ROOT}:/src" -w /src golang:1.22-alpine \
    sh -c "apk add --no-cache git gcc musl-dev >/dev/null && go mod tidy && CGO_ENABLED=1 go build -o /dev/null ./api/cmd/badsector-api && CGO_ENABLED=1 go build -o /dev/null ./worker/cmd/badsector-worker"
}

ui_build() {
  docker run --rm -v "${ROOT}/ui:/app" -w /app node:20-alpine \
    sh -c "npm install --no-audit --no-fund && npm run build"
}

compose_build() {
  if docker compose version >/dev/null 2>&1; then
    docker compose build
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose build
  else
    echo "docker compose not found" >&2
    return 1
  fi
}

run_step "Go (api + worker)" go_build
run_step "UI (tsc + vite)" ui_build
run_step "Docker Compose (all images)" compose_build

echo ""
if [ "$fail" -ne 0 ]; then
  echo "Validation FAILED — fix errors above before deploy." >&2
  exit 1
fi

echo "Validation passed. Safe to: git push && docker compose up -d --build"
