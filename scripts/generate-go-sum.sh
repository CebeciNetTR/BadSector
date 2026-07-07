#!/usr/bin/env bash
# Generate go.sum (run from repo root, requires Docker)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm -v "${ROOT}:/src" -w /src golang:1.22-alpine \
  sh -c "apk add --no-cache git && go mod tidy && go build ./..."
echo "go.sum updated. Commit and push."
