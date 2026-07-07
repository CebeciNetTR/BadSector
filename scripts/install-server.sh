#!/usr/bin/env bash
# BadSector — first-time server install (Ubuntu/Debian + Docker)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USER/BadSector/main/scripts/install-server.sh | bash
#   # or after clone:
#   ./scripts/install-server.sh
#
# Optional args:
#   ./scripts/install-server.sh [install_dir]
#   BADSECTOR_REPO=https://github.com/YOUR_USER/BadSector.git ./scripts/install-server.sh

set -euo pipefail

REPO="${BADSECTOR_REPO:-}"
INSTALL_DIR="${1:-/opt/badsector}"
BRANCH="${BADSECTOR_BRANCH:-main}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing: $1"
    exit 1
  }
}

install_docker_if_missing() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return 0
  fi

  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
}

clone_or_update() {
  if [ -d "${INSTALL_DIR}/.git" ]; then
    echo "Updating ${INSTALL_DIR}..."
    git -C "${INSTALL_DIR}" fetch origin
    git -C "${INSTALL_DIR}" checkout "${BRANCH}"
    git -C "${INSTALL_DIR}" pull origin "${BRANCH}"
    return 0
  fi

  if [ -n "${REPO}" ]; then
    echo "Cloning ${REPO} → ${INSTALL_DIR}"
    git clone --branch "${BRANCH}" --depth 1 "${REPO}" "${INSTALL_DIR}"
    return 0
  fi

  if [ -f "$(dirname "$0")/../docker-compose.yml" ]; then
    INSTALL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    echo "Using existing checkout: ${INSTALL_DIR}"
    return 0
  fi

  echo "Set BADSECTOR_REPO or run from a cloned repository."
  echo "Example: BADSECTOR_REPO=https://github.com/YOUR_USER/BadSector.git $0"
  exit 1
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
  fi

  need_cmd git
  need_cmd curl
  install_docker_if_missing

  clone_or_update
  cd "${INSTALL_DIR}"

  if [ ! -f .env ]; then
    cp .env.example .env
    echo ""
    echo "Created ${INSTALL_DIR}/.env — edit secrets before going live:"
    echo "  nano ${INSTALL_DIR}/.env"
    echo ""
    echo "Required for production:"
    echo "  BADSECTOR_ACME_EMAIL=..."
    echo "  BADSECTOR_HAPROXY_CONFIG=live"
    echo "  MAXMIND_LICENSE_KEY=..."
    echo "  BADSECTOR_JWT_SECRET=... (random)"
    echo "  BADSECTOR_AUTH_DISABLED=false"
    echo ""
  fi

  ./scripts/setup-dev-data.sh
  docker compose up -d --build

  echo ""
  echo "BadSector started."
  echo "  Dashboard : http://$(hostname -I | awk '{print $1}'):3000"
  echo "  API       : http://$(hostname -I | awk '{print $1}'):8080/health"
  echo "  Edge HTTP : http://$(hostname -I | awk '{print $1}'):9080  (dev)"
  echo "  Edge TLS  : https://YOUR_DOMAIN  (after cert + BADSECTOR_HAPROXY_CONFIG=live)"
  echo ""
  echo "Logs: docker compose -f ${INSTALL_DIR}/docker-compose.yml logs -f"
}

main "$@"
