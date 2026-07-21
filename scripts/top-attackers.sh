#!/usr/bin/env bash
# BadSector — en gurultulu IP'leri goster / banla (OVH + ipset).
#
# Kullanim:
#   bash scripts/top-attackers.sh           # ozet
#   bash scripts/top-attackers.sh 30
#   bash scripts/top-attackers.sh 200 ban

set -eu
# pipefail YOK: head|sort SIGPIPE script'i oldurmesin

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
N="${1:-20}"
MODE="${2:-}"
COMPOSE=(docker compose)
SOCK=/var/run/haproxy/admin.sock
IPSET_NAME=bs_banned
BAN_TTL="${BAN_TTL:-7200}"
TRUSTED_IPS="${BADSECTOR_TRUSTED_IPS:-}"

if [[ -f .env ]]; then
  TRUSTED_LINE=$(grep -E '^BADSECTOR_TRUSTED_IPS=' .env 2>/dev/null | tail -1 || true)
  if [[ -n "$TRUSTED_LINE" ]]; then
    TRUSTED_IPS="${TRUSTED_LINE#BADSECTOR_TRUSTED_IPS=}"
    TRUSTED_IPS="${TRUSTED_IPS%\"}"
    TRUSTED_IPS="${TRUSTED_IPS#\"}"
  fi
fi

haproxy_cmd() {
  echo "$1" | "${COMPOSE[@]}" exec -T haproxy socat stdio "${SOCK}" 2>/dev/null || true
}

is_trusted() {
  local ip="$1" part
  IFS=',' read -ra _parts <<< "$TRUSTED_IPS"
  for part in "${_parts[@]}"; do
    part="${part#"${part%%[![:space:]]*}"}"
    part="${part%"${part##*[![:space:]]}"}"
    [[ "$part" == "$ip" ]] && return 0
  done
  return 1
}

redis_cli() {
  # stdin'i yutma (while-read / mapfile bozulmasin)
  "${COMPOSE[@]}" exec -T redis redis-cli "$@" </dev/null 2>/dev/null || true
}

ban_one() {
  local ip="$1"
  local why="${2:-}"
  if is_trusted "$ip"; then
    echo "SKIP trusted $ip"
    return 0
  fi
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 0
  fi
  if ipset -exist add "$IPSET_NAME" "$ip" timeout "$BAN_TTL" 2>/dev/null; then
    redis_cli SETEX "bs:ban:$ip" "$BAN_TTL" "1" >/dev/null
    redis_cli ZREM bs:ip_hits "$ip" >/dev/null
    redis_cli ZREM bs:ip_seen "$ip" >/dev/null
    echo "BANNED ${why} $ip"
  else
    echo "FAIL ipset $ip"
  fi
}

parse_table() {
  haproxy_cmd "show table fe_https" | sed 's/[, ]/\n/g' | awk '
    BEGIN { ip=""; rate=0; conn=0 }
    /^key=/ { if (ip != "") print rate, conn, ip; ip=substr($0,5); rate=0; conn=0; next }
    /^http_req_rate=/ { rate=substr($0,15)+0; next }
    /^conn_cur=/ { conn=substr($0,10)+0; next }
    END { if (ip != "") print rate, conn, ip }
  '
}

TABLE_FILE=$(mktemp)
HIT_FILE=$(mktemp)
CONN_FILE=$(mktemp)
trap 'rm -f "$TABLE_FILE" "$HIT_FILE" "$CONN_FILE"' EXIT

parse_table > "$TABLE_FILE" || true

echo "=== Redis bs:ip_hits top ${N} ==="
redis_cli ZREVRANGE bs:ip_hits 0 $((N - 1)) WITHSCORES | tr -d '\r' || true

echo ""
echo "=== TLS flood adaylari (conn yuksek, rate dusuk) ==="
awk '$2 >= 3 { print $2, $1, $3 }' "$TABLE_FILE" | sort -nr -k1,1 | head -n "$N" \
  | awk '{printf "conn=%s rate=%s/10s  %s\n", $1, $2, $3}' || true

echo ""
echo "=== HTTP rate yuksek ==="
if ! awk '$1 > 0 { found=1; print $1, $2, $3 }' "$TABLE_FILE" | sort -nr -k1,1 | head -n "$N" \
  | awk '{printf "rate=%s/10s conn=%s  %s\n", $1, $2, $3}'; then
  :
fi
if ! awk '$1 > 0 { exit 1 }' "$TABLE_FILE"; then
  :
else
  echo "(yok — TLS asamasinda)"
fi

echo ""
echo "=== ipset ==="
ipset list bs_banned 2>/dev/null | awk '/Number of entries/ {print}' || echo "ipset yok"

# ss flood'da takilabilir — sadece ozet modda, kisa timeout
if [[ "$MODE" != "ban" ]] && command -v timeout >/dev/null 2>&1; then
  echo ""
  echo "=== Host :443 established (ss, 3s timeout) ==="
  timeout 3 ss -tn state established '( sport = :443 or dport = :443 )' 2>/dev/null \
    | awk 'NR>1 {
        n=split($NF, a, ":"); ip=a[1]
        if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) c[ip]++
      }
      END { for (i in c) print c[i], i }' \
    | sort -nr | head -n "$N" \
    | awk '{printf "estab=%s  %s\n", $1, $2}' || echo "(ss timeout/skip)"
fi

if [[ "$MODE" == "ban" ]]; then
  awk '$2 >= 3 { print $3 }' "$TABLE_FILE" | sort -u | head -n "$N" > "$CONN_FILE" || true
  redis_cli ZREVRANGE bs:ip_hits 0 $((N - 1)) | tr -d '\r' > "$HIT_FILE" || true

  echo ""
  echo "=== BAN stick-table ($(wc -l < "$CONN_FILE") IP) ==="
  while IFS= read -r ip || [[ -n "${ip:-}" ]]; do
    [[ -z "$ip" ]] && continue
    ban_one "$ip" "conn" || true
  done < "$CONN_FILE"

  echo ""
  echo "=== BAN redis hits ($(wc -l < "$HIT_FILE") IP) ==="
  while IFS= read -r ip || [[ -n "${ip:-}" ]]; do
    [[ -z "$ip" ]] && continue
    ban_one "$ip" "hits" || true
  done < "$HIT_FILE"

  echo ""
  echo "=== ipset sonra ==="
  ipset list bs_banned 2>/dev/null | awk '/Number of entries/ {print}' || true
fi

echo ""
echo "OK. Toplu ban: bash scripts/top-attackers.sh 200 ban"
