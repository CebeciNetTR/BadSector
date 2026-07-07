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

validate_pem() {
  local f="$1"
  [[ -f "${f}" && -s "${f}" ]] || return 1
  openssl x509 -in "${f}" -noout 2>/dev/null || return 1
  openssl pkey -in "${f}" -noout 2>/dev/null || return 1
  return 0
}

rebuild_pem_from_private() {
  local base="$1"
  local crt="${PRIVATE}/${base}.crt"
  local key="${PRIVATE}/${base}.key"
  local out="${HAPROXY}/${base}.pem"
  if [[ -f "${crt}" && -f "${key}" ]]; then
    cat "${crt}" "${key}" > "${out}"
    chmod 644 "${out}"
    echo "Rebuilt ${out} from private/"
    return 0
  fi
  return 1
}

shopt -s nullglob
for f in "${HAPROXY}"/*.pem; do
  base="$(basename "${f}" .pem)"
  if validate_pem "${f}"; then
    echo "OK: $(basename "${f}")"
    continue
  fi
  echo "Invalid or empty PEM, fixing: $(basename "${f}")"
  rm -f "${f}"
  rebuild_pem_from_private "${base}" || true
done
shopt -u nullglob

has_valid_pem=false
shopt -s nullglob
for f in "${HAPROXY}"/*.pem; do
  if validate_pem "${f}"; then
    has_valid_pem=true
    break
  fi
done
shopt -u nullglob

if [[ "${has_valid_pem}" == "false" ]]; then
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

# HAProxy container runs as non-root; PEMs must be readable on the bind mount.
chmod 644 "${HAPROXY}"/*.pem 2>/dev/null || true

echo "HAProxy certs (${HAPROXY}):"
ls -la "${HAPROXY}/" || true
echo "private/:"
ls -la "${PRIVATE}/" 2>/dev/null || true
echo "acme/:"
ls -la "${ACME}/" 2>/dev/null || true
