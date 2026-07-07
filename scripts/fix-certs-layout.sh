#!/usr/bin/env bash
# Fix HAProxy cert directory layout (run on server after git pull).
#
# HAProxy crt directory loads every file in the root. Keep only combined *.pem there.
# ACME account JSON -> data/certs/acme/
# Split .crt/.key     -> data/certs/private/
#
# Usage:
#   cd /opt/badsector && bash scripts/fix-certs-layout.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERTS="${ROOT}/data/certs"
ACME="${CERTS}/acme"
PRIVATE="${CERTS}/private"

mkdir -p "${ACME}" "${PRIVATE}"

shopt -s nullglob

# Move legacy ACME account JSON out of HAProxy cert dir.
for f in "${CERTS}"/acme-*.json; do
  echo "Moving $(basename "${f}") -> acme/"
  mv "${f}" "${ACME}/"
done

# Move split cert/key out of HAProxy root (temp.crt expects temp.crt.key and breaks bind).
for f in "${CERTS}"/*.crt "${CERTS}"/*.key; do
  echo "Moving $(basename "${f}") -> private/"
  mv "${f}" "${PRIVATE}/"
done

shopt -u nullglob

rm -f "${CERTS}/.gitkeep"

# Bootstrap a temporary combined PEM so live HAProxy can bind :443 before LE issue.
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
  tmpcrt="$(mktemp)"
  tmpkey="$(mktemp)"
  openssl req -x509 -newkey rsa:2048 \
    -keyout "${tmpkey}" \
    -out "${tmpcrt}" \
    -days 7 -nodes \
    -subj "/CN=localhost" 2>/dev/null
  cat "${tmpcrt}" "${tmpkey}" > "${CERTS}/temp.pem"
  rm -f "${tmpcrt}" "${tmpkey}"
  chmod 644 "${CERTS}/temp.pem"
  echo "Created ${CERTS}/temp.pem (remove after real Let's Encrypt cert is issued)"
fi

echo "Cert layout OK (HAProxy root should be *.pem only):"
ls -la "${CERTS}/" || true
echo "private/:"
ls -la "${PRIVATE}/" 2>/dev/null || true
echo "acme/:"
ls -la "${ACME}/" 2>/dev/null || true
