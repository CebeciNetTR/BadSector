#!/usr/bin/env bash
# BadSector - HAProxy site bazli request-rate esigini restart'siz degistir.
#
# HAProxy'nin request-rate limiti varsayilan olarak 20 istek/10s'dir (tum siteler
# icin ortak). Bu script, tek bir host icin bu esigi anlik olarak (admin socket
# uzerinden, HAProxy restart etmeden) degistirir VE degisikligi diskteki map
# dosyasina yazar (container yeniden baslasa/rebuild olsa da kaybolmaz).
#
# Kullanim:
#   bash scripts/haproxy-site-limit.sh set <host> <limit>     # ozel esik ata (orn: 500)
#   bash scripts/haproxy-site-limit.sh unlimited <host>       # bu site icin limiti kapat (-1)
#   bash scripts/haproxy-site-limit.sh clear <host>           # haritadan sil, varsayilan (20) esige don
#   bash scripts/haproxy-site-limit.sh list                   # canli haritayi goster
#
# Not: <host> tam olarak istemcinin gonderdigi Host header'iyla (kucuk harf) eslesmeli.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP_FILE="${ROOT}/data/haproxy/site-ratelimit.map"
SOCK="/var/run/haproxy/admin.sock"
# Container icindeki map referansi (config'te yuklendigi path ile birebir ayni olmali)
MAP_ID="/usr/local/etc/haproxy/maps/site-ratelimit.map"
SERVICE="${BADSECTOR_HAPROXY_SERVICE:-haproxy}"

compose() {
  bash "${ROOT}/scripts/compose.sh" "$@"
}

haproxy_exec() {
  # HAProxy container'i icinde admin socket'e komut gonderir.
  compose exec -T "${SERVICE}" sh -c "echo '$1' | socat stdio unix-connect:${SOCK}"
}

usage() {
  sed -n '2,17p' "$0"
  exit 1
}

[[ $# -lt 1 ]] && usage
ACTION="$1"; shift

case "${ACTION}" in
  set)
    [[ $# -eq 2 ]] || usage
    HOST="$(echo "$1" | tr '[:upper:]' '[:lower:]')"; LIMIT="$2"
    if ! [[ "${LIMIT}" =~ ^-?[0-9]+$ ]]; then
      echo "Limit bir tamsayi olmali (orn: 500, veya -1)." >&2
      exit 1
    fi
    # HAProxy'de "set map" sadece VAR OLAN anahtari gunceller; yeni host icin hata verir.
    # Idempotent olmasi icin once sil (yoksa hatayi yut), sonra ekle.
    haproxy_exec "del map ${MAP_ID} ${HOST}" >/dev/null 2>&1 || true
    haproxy_exec "add map ${MAP_ID} ${HOST} ${LIMIT}"
    grep -v -E "^${HOST}[[:space:]]" "${MAP_FILE}" > "${MAP_FILE}.tmp" 2>/dev/null || true
    echo "${HOST} ${LIMIT}" >> "${MAP_FILE}.tmp"
    mv "${MAP_FILE}.tmp" "${MAP_FILE}"
    echo "OK: ${HOST} -> ${LIMIT} (canli + diskte kalici)"
    ;;
  unlimited)
    [[ $# -eq 1 ]] || usage
    "$0" set "$1" -1
    ;;
  clear)
    [[ $# -eq 1 ]] || usage
    HOST="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    haproxy_exec "del map ${MAP_ID} ${HOST}" >/dev/null 2>&1 || true
    grep -v -E "^${HOST}[[:space:]]" "${MAP_FILE}" > "${MAP_FILE}.tmp" 2>/dev/null || true
    mv "${MAP_FILE}.tmp" "${MAP_FILE}"
    echo "OK: ${HOST} haritadan silindi, varsayilan esige (20) dondu"
    ;;
  list)
    haproxy_exec "show map ${MAP_ID}"
    ;;
  *)
    usage
    ;;
esac
