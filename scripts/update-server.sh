#!/usr/bin/env bash
# Update running BadSector from git and rebuild containers.
#
# Policy: all product changes land in git first; servers only pull + this script.
#
# Usage (on server):
#   cd /opt/badsector && bash scripts/update-server.sh          # fast (default)
#   cd /opt/badsector && bash scripts/update-server.sh --full   # slow: no-cache rebuild all
#   cd /opt/badsector && bash scripts/update-server.sh --hard-reset  # discard local tracked diffs
#
# Git: normal updates use fast-forward merge (seconds). Hard reset only when --hard-reset
#      or when ff-only fails (e.g. server-side edits to tracked files).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

compose() {
  bash "${ROOT}/scripts/compose.sh" "$@"
}

BRANCH="${BADSECTOR_BRANCH:-main}"
MODE="fast"
HARD_RESET=false
SERVICES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)
      MODE="full"
      ;;
    --fast)
      MODE="fast"
      ;;
    --hard-reset)
      HARD_RESET=true
      ;;
    --services)
      shift
      IFS=',' read -r -a SERVICES <<< "${1:-}"
      ;;
    -h|--help)
      sed -n '2,12p' "$0"
      echo ""
      echo "  --fast         git ff-only + cached docker build (default)"
      echo "  --full         git reset --hard + docker build --no-cache (all edge services)"
      echo "  --hard-reset   always git reset --hard origin/${BRANCH} before build"
      echo "  --services     comma list, e.g. engine,api (default: auto from git diff)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
  shift
done

pull_git() {
  echo "==> Pull ${BRANCH}"
  git fetch origin
  git checkout "${BRANCH}"

  if [[ "${HARD_RESET}" == true ]] || [[ "${MODE}" == "full" ]]; then
    git reset --hard "origin/${BRANCH}"
    echo "    hard reset -> $(git log -1 --oneline)"
    return
  fi

  if git diff --quiet HEAD "origin/${BRANCH}"; then
    echo "    already up to date ($(git log -1 --oneline))"
    return
  fi

  if git merge --ff-only "origin/${BRANCH}"; then
    echo "    fast-forward -> $(git log -1 --oneline)"
    return
  fi

  echo "    ff-only failed (local tracked changes?) — reset --hard"
  git reset --hard "origin/${BRANCH}"
  echo "    $(git log -1 --oneline)"
}

services_from_diff() {
  local prev="${1}"
  local out=()
  local seen=""

  add() {
    local s="$1"
    [[ " ${seen} " == *" ${s} "* ]] && return
    seen="${seen} ${s}"
    out+=("$s")
  }

  if git diff --name-only "${prev}" HEAD | grep -qE '^(engine/|engine/Dockerfile)'; then
    add haproxy
    add engine
  fi
  if git diff --name-only "${prev}" HEAD | grep -qE '^(api/|internal/|worker/|go\.mod|go\.sum|Dockerfile)'; then
    add api
    add worker
  fi
  if git diff --name-only "${prev}" HEAD | grep -qE '^ui/'; then
    add ui
  fi
  if git diff --name-only "${prev}" HEAD | grep -qE '^deploy/haproxy/'; then
    add haproxy
  fi
  if git diff --name-only "${prev}" HEAD | grep -qE '^(docker-compose\.yml|scripts/compose\.sh)'; then
    add haproxy
    add engine
    add api
    add worker
    add ui
  fi

  if [[ ${#out[@]} -eq 0 ]]; then
    out=(haproxy engine api worker ui)
  fi

  printf '%s\n' "${out[@]}"
}

PREV_HEAD="$(git rev-parse HEAD)"
pull_git
NEW_HEAD="$(git rev-parse HEAD)"

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  if [[ "${MODE}" == "full" ]]; then
    SERVICES=(haproxy engine api worker ui)
  elif [[ "${PREV_HEAD}" == "${NEW_HEAD}" ]]; then
    echo "==> No git changes — skipping rebuild (use --full to force)"
    SERVICES=()
  else
    mapfile -t SERVICES < <(services_from_diff "${PREV_HEAD}")
    echo "==> Changed services: ${SERVICES[*]}"
  fi
fi

echo "==> Data dirs + cert layout"
bash "${ROOT}/scripts/setup-dev-data.sh"
bash "${ROOT}/scripts/fix-certs-layout.sh"

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "==> Recreate containers (no rebuild)"
  compose up -d
else
  echo "==> Rebuild (${MODE}): ${SERVICES[*]}"
  if [[ "${MODE}" == "full" ]]; then
    compose build --no-cache "${SERVICES[@]}"
  else
    compose build "${SERVICES[@]}"
  fi
  compose up -d --build
fi

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
echo "Update complete (${MODE})."
