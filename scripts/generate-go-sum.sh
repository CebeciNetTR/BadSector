#!/usr/bin/env bash
# Generate go.sum (run from repo root, requires Docker)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm -v "${ROOT}:/src" -w /src golang:1.22-alpine \
  sh -c "apk add --no-cache git gcc musl-dev && go mod tidy && CGO_ENABLED=1 go build ./api/cmd/badsector-api ./worker/cmd/badsector-worker"
echo "go.sum updated. Commit and push."
