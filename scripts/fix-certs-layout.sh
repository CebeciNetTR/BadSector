#!/usr/bin/env bash
# Fix cert directory layout (run on server after git pull).
#
# Layout:
#   data/certs/haproxy/  -> mounted into HAProxy (combined *.pem only)
#   data/certs/private/  -> split .crt / .key (API storage)
#   data/certs/acme/     -> ACME account JSON
#
# Usage:
#   cd /opt/badsector && bash scripts/fix-certs-layout.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERTS="${ROOT}/data/certs"
HAPROXY="${CERTS}/haproxy"
ACME="${CERTS}/acme"
PRIVATE="${CERTS}/private"

mkdir -p "${HAPROXY}" "${ACME}" "${PRIVATE}"

shopt -s nullglob

for f in "${CERTS}"/acme-*.json; do
  echo "Moving $(basename "${f}") -> acme/"
  mv "${f}" "${ACME}/"
done

for f in "${CERTS}"/*.crt "${CERTS}"/*.key; do
  echo "Moving $(basename "${f}") -> private/"
  mv "${f}" "${PRIVATE}/"
done

for f in "${CERTS}"/*.pem; do
  base="$(basename "${f}")"
  if [[ ! -f "${HAPROXY}/${base}" ]]; then
    echo "Moving ${base} -> haproxy/"
    mv "${f}" "${HAPROXY}/"
  fi
done

for f in "${PRIVATE}"/*.pem; do
  base="$(basename "${f}")"
  if [[ ! -f "${HAPROXY}/${base}" ]]; then
    echo "Copying ${base} from private/ -> haproxy/"
    cp "${f}" "${HAPROXY}/${base}"
  fi
done

shopt -u nullglob

rm -f "${CERTS}/.gitkeep"

has_pem=false
shopt -s nullglob
for f in "${HAPROXY}"/*.pem; do
  if [[ -f "${f}" && -s "${f}" ]]; then
    has_pem=true
    break
  fi
done
shopt -u nullglob

if [[ "${has_pem}" == "false" ]]; then
  echo "No .pem in ${HAPROXY}; creating bootstrap temp.pem..."
  tmpcrt="$(mktemp)"
  tmpkey="$(mktemp)"
  openssl req -x509 -newkey rsa:2048 \
    -keyout "${tmpkey}" \
    -out "${tmpcrt}" \
    -days 7 -nodes \
    -subj "/CN=localhost" 2>/dev/null
  cat "${tmpcrt}" "${tmpkey}" > "${HAPROXY}/temp.pem"
  rm -f "${tmpcrt}" "${tmpkey}"
  chmod 644 "${HAPROXY}/temp.pem"
  echo "Created ${HAPROXY}/temp.pem (remove after real Let's Encrypt cert is issued)"
fi

echo "HAProxy certs (${HAPROXY}):"
ls -la "${HAPROXY}/" || true
echo "private/:"
ls -la "${PRIVATE}/" 2>/dev/null || true
echo "acme/:"
ls -la "${ACME}/" 2>/dev/null || true
