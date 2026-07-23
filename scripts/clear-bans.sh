#!/bin/bash

# BadSector — tum ban'lari bosalt (Redis + host ipset).

# Kullanim (sunucuda /opt/badsector):

#   sudo ./scripts/clear-bans.sh

# Tek IP ac:

#   sudo ./scripts/clear-bans.sh 1.2.3.4

# Kalici ban'lari da sil:

#   sudo ./scripts/clear-bans.sh --all



set -euo pipefail



ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"



IPSET_NAME="${IPSET_NAME:-bs_banned}"

PERM_IPSET="${PERM_IPSET:-bs_banned_perm}"

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

  redis_cli DEL "bs:ban_strikes:day:$ip" >/dev/null || true

  redis_cli DEL "bs:ban_strikes:week:$ip" >/dev/null || true

  if command -v ipset >/dev/null 2>&1; then

    ipset del "$IPSET_NAME" "$ip" 2>/dev/null || true

    ipset del "$PERM_IPSET" "$ip" 2>/dev/null || true

  fi

}



clear_all() {

  local include_perm="${1:-false}"

  echo "Redis bs:ban:* siliniyor..."

  local n=0

  local keys

  keys=$(redis_cli --scan --pattern 'bs:ban:*' 2>/dev/null || true)

  if [[ -n "${keys:-}" ]]; then

    while IFS= read -r k; do

      [[ -z "$k" ]] && continue

      if [[ "$include_perm" != "true" ]]; then
        local ttl val
        ttl=$(redis_cli TTL "$k" 2>/dev/null || true)
        val=$(redis_cli GET "$k" 2>/dev/null || true)
        if [[ "$ttl" == "-1" ]] || [[ "$val" == permanent:* ]]; then
          continue
        fi
      fi

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

    if [[ "$include_perm" == "true" ]]; then

      if ipset list "$PERM_IPSET" &>/dev/null; then

        ipset flush "$PERM_IPSET"

        echo "ipset '$PERM_IPSET' flush edildi (kalici banlar)"

      fi

      redis_cli --scan --pattern 'bs:ban_strikes:*' 2>/dev/null | while IFS= read -r sk; do

        [[ -z "$sk" ]] && continue

        redis_cli DEL "$sk" >/dev/null || true

      done

    else

      echo "Kalici ban korundu ($PERM_IPSET + Redis TTL=-1 / permanent:*)"

    fi

  else

    echo "ipset yok — sadece Redis temizlendi"

  fi



  # Hit sayaci (watcher esigi) — istege bagli sifirla

  redis_cli DEL bs:ip_hits >/dev/null 2>&1 || true

  redis_cli DEL bs:ip_seen >/dev/null 2>&1 || true

  echo "bs:ip_hits / bs:ip_seen sifirlandi"

}



if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then

  echo "Usage: sudo $0 [IP|--all]"

  echo "  (no args)  flush temporary bans (keep permanent)"

  echo "  IP         unban one IP (incl. permanent)"

  echo "  --all      flush temporary + permanent bans"

  exit 0

fi



if [[ $# -ge 1 && "${1:-}" == "--all" ]]; then

  clear_all true

elif [[ $# -ge 1 ]]; then

  clear_one "$1"

else

  clear_all false

fi



echo "OK — engine ban cache ~5s icinde dusar (veya: docker compose restart engine)"

