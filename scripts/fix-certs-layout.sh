#!/usr/bin/env bash
# Fix HAProxy cert directory layout (run on server after git pull).
#
# HAProxy loads every file in /etc/haproxy/certs/ as TLS material.
# ACME account JSON must live in data/certs/acme/ — not beside .pem files.
#
# Usage:
#   cd /opt/badsector && bash scripts/fix-certs-layout.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERTS="${ROOT}/data/certs"
ACME="${CERTS}/acme"

mkdir -p "${ACME}"

# Move legacy ACME account JSON out of HAProxy cert dir.
shopt -s nullglob
for f in "${CERTS}"/acme-*.json; do
  echo "Moving $(basename "${f}") -> acme/"
  mv "${f}" "${ACME}/"
done
shopt -u nullglob

# Empty placeholder breaks HAProxy directory scan on some setups.
rm -f "${CERTS}/.gitkeep"

# Bootstrap a temporary cert so live HAProxy can bind :443 before LE issue.
has_pem=false
shopt -s nullglob
for f in "${CERTS}"/*.pem; do
  if [[ -f "${f}" && -s "${f}" ]]; then
    has_pem=true
    break
  fi
done
shopt -u nullglob

if [[ "${has_pem}" == "false" ]]; then
  echo "No .pem in ${CERTS}; creating temporary bootstrap cert (temp.pem)..."
  openssl req -x509 -newkey rsa:2048 \
    -keyout "${CERTS}/temp.key" \
    -out "${CERTS}/temp.crt" \
    -days 7 -nodes \
    -subj "/CN=localhost" 2>/dev/null
  cat "${CERTS}/temp.crt" "${CERTS}/temp.key" > "${CERTS}/temp.pem"
  chmod 644 "${CERTS}/temp.pem"
  echo "Created ${CERTS}/temp.pem (remove after real Let's Encrypt cert is issued)"
fi

echo "Cert layout OK:"
ls -la "${CERTS}/" || true
echo "ACME accounts:"
ls -la "${ACME}/" 2>/dev/null || true
