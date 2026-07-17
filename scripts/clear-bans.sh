#!/bin/bash
# BadSector — tum ban'lari bosalt (Redis + host ipset).
# Kullanim (sunucuda /opt/badsector):
#   sudo ./scripts/clear-bans.sh
# Tek IP ac:
#   sudo ./scripts/clear-bans.sh 1.2.3.4

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IPSET_NAME="${IPSET_NAME:-bs_banned}"
COMPOSE=(docker compose)
if [[ -f docker-compose.override.yml ]]; then
  :
fi

redis_cli() {
  "${COMPOSE[@]}" exec -T redis redis-cli "$@"
}

clear_one() {
  local ip="$1"
  echo "Unban: $ip"
  redis_cli DEL "bs:ban:$ip" >/dev/null || true
  if command -v ipset >/dev/null 2>&1; then
    ipset del "$IPSET_NAME" "$ip" 2>/dev/null || true
  fi
}

clear_all() {
  echo "Redis bs:ban:* siliniyor..."
  local n=0
  local keys
  keys=$(redis_cli --scan --pattern 'bs:ban:*' 2>/dev/null || true)
  if [[ -n "${keys:-}" ]]; then
    while IFS= read -r k; do
      [[ -z "$k" ]] && continue
      redis_cli DEL "$k" >/dev/null || true
      n=$((n + 1))
    done <<< "$keys"
  fi
  echo "  silinen Redis ban: $n"

  if command -v ipset >/dev/null 2>&1; then
    if ipset list "$IPSET_NAME" &>/dev/null; then
      ipset flush "$IPSET_NAME"
      echo "ipset '$IPSET_NAME' flush edildi"
    else
      echo "ipset '$IPSET_NAME' yok (atlandi)"
    fi
  else
    echo "ipset yok — sadece Redis temizlendi"
  fi

  # Hit sayaci (watcher esigi) — istege bagli sifirla
  redis_cli DEL bs:ip_hits >/dev/null 2>&1 || true
  echo "bs:ip_hits sifirlandi"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: sudo $0 [IP]"
  echo "  (no args)  flush all bans"
  echo "  IP         unban one IP"
  exit 0
fi

if [[ $# -ge 1 ]]; then
  clear_one "$1"
else
  clear_all
fi

echo "OK — engine ban cache ~5s icinde dusar (veya: docker compose restart engine)"
