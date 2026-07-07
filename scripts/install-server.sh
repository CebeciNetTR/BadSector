#!/usr/bin/env bash
# BadSector — first-time server install (Ubuntu/Debian + Docker)
#
# Usage (always bash, not sh):
#   cd /opt/badsector
#   bash scripts/install-server.sh
#
# Optional:
#   bash scripts/install-server.sh /opt/badsector

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Windows CRLF → Linux LF (GitHub Desktop / Windows checkout)
for f in "${ROOT}"/scripts/*.sh; do
  if [ -f "$f" ]; then
    sed -i 's/\r$//' "$f" 2>/dev/null || sed -i '' 's/\r$//' "$f" 2>/dev/null || true
    chmod +x "$f" 2>/dev/null || true
  fi
done

REPO="${BADSECTOR_REPO:-}"
INSTALL_DIR="${1:-${ROOT}}"
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
    echo "Using git checkout: ${INSTALL_DIR}"
    return 0
  fi

  if [ -n "${REPO}" ]; then
    echo "Cloning ${REPO} → ${INSTALL_DIR}"
    git clone --branch "${BRANCH}" --depth 1 "${REPO}" "${INSTALL_DIR}"
    return 0
  fi

  if [ -f "${INSTALL_DIR}/docker-compose.yml" ]; then
    echo "Using existing directory: ${INSTALL_DIR}"
    return 0
  fi

  echo "Set BADSECTOR_REPO or clone the repo first."
  echo "Example: git clone https://github.com/CebeciNetTR/BadSector.git /opt/badsector"
  exit 1
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash scripts/install-server.sh"
    exit 1
  fi

  need_cmd git
  need_cmd curl
  need_cmd bash
  install_docker_if_missing

  clone_or_update
  cd "${INSTALL_DIR}"

  if [ ! -f .env ]; then
    cp .env.example .env
    echo ""
    echo "Created ${INSTALL_DIR}/.env — edit before production:"
    echo "  nano ${INSTALL_DIR}/.env"
    echo ""
  fi

  bash "${INSTALL_DIR}/scripts/setup-dev-data.sh"
  docker compose up -d --build

  echo ""
  echo "BadSector started."
  echo "  Dashboard : http://$(hostname -I | awk '{print $1}'):3000"
  echo "  API       : http://$(hostname -I | awk '{print $1}'):8080/health"
  echo "  Edge HTTP : http://$(hostname -I | awk '{print $1}'):9080"
  echo ""
  echo "Logs: docker compose -f ${INSTALL_DIR}/docker-compose.yml logs -f"
}

main "$@"
