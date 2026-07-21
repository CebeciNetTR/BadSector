#!/usr/bin/env bash
# BadSector — en gurultulu IP'leri goster (OVH firewall icin).
#
# ONEMLI: ipset (kernel) banli IP paketleri HAProxy'ye ULASMAZ → hit sayilmaz.
# rate=0 + conn>0 = tipik TLS/handshake flood (HTTP yok, baglanti tutuyor).
#
# Kullanim:
#   bash scripts/top-attackers.sh           # ozet
#   bash scripts/top-attackers.sh 30        # top N
#   bash scripts/top-attackers.sh 200 ban   # conn + Redis top → ipset (trusted haric)

set -euo pipefail

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

# ipset: -exist KOMUTTAN ONCE olmali (sonda parse edilmez → "already in set" fail)
ban_one() {
  local ip="$1"
  local why="${2:-}"
  if is_trusted "$ip"; then
    echo "SKIP trusted $ip"
    return 0
  fi
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$ip" =~ : ]]; then
    return 0
  fi
  if ipset -exist add "$IPSET_NAME" "$ip" timeout "$BAN_TTL" 2>/dev/null; then
    "${COMPOSE[@]}" exec -T redis redis-cli SETEX "bs:ban:$ip" "$BAN_TTL" "1" >/dev/null 2>&1 || true
    "${COMPOSE[@]}" exec -T redis redis-cli ZREM bs:ip_hits "$ip" >/dev/null 2>&1 || true
    "${COMPOSE[@]}" exec -T redis redis-cli ZREM bs:ip_seen "$ip" >/dev/null 2>&1 || true
    echo "BANNED ${why} $ip"
    return 0
  fi
  echo "FAIL $ip"
  return 1
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

# Stick-table bir kez (ban + gosterim ayni snapshot)
TABLE_FILE=$(mktemp)
trap 'rm -f "$TABLE_FILE"' EXIT
parse_table > "$TABLE_FILE" || true

echo "=== Redis bs:ip_hits (ban oncesi kumulatif) top ${N} ==="
"${COMPOSE[@]}" exec -T redis redis-cli ZREVRANGE bs:ip_hits 0 $((N - 1)) WITHSCORES 2>/dev/null | tr -d '\r' || true

echo ""
echo "=== TLS flood adaylari: conn_cur yuksek, rate dusuk (OVH oncelik) ==="
awk '$2 >= 3 { print $2, $1, $3 }' "$TABLE_FILE" | sort -nr -k1,1 | head -n "$N" \
  | awk '{printf "conn=%s rate=%s/10s  %s\n", $1, $2, $3}'

echo ""
echo "=== HTTP rate yuksek (gercek istek flood) ==="
HTTP_N=$(awk '$1 > 0 { c++ } END { print c+0 }' "$TABLE_FILE")
if [[ "$HTTP_N" -eq 0 ]]; then
  echo "(yok — trafik HTTP'ye zor ulasiyor; TLS asamasinda)"
else
  awk '$1 > 0 { print $1, $2, $3 }' "$TABLE_FILE" | sort -nr -k1,1 | head -n "$N" \
    | awk '{printf "rate=%s/10s conn=%s  %s\n", $1, $2, $3}'
fi

echo ""
echo "=== Host :443 established (ss) top ${N} ==="
if command -v ss >/dev/null 2>&1; then
  ss -tn state established '( sport = :443 or dport = :443 )' 2>/dev/null \
    | awk 'NR>1 {
        n=split($NF, a, ":")
        ip=a[1]
        if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) c[ip]++
      }
      END { for (i in c) print c[i], i }' \
    | sort -nr \
    | head -n "$N" \
    | awk '{printf "estab=%s  %s\n", $1, $2}'
else
  echo "(ss yok)"
fi

echo ""
echo "=== ipset ==="
ipset list bs_banned 2>/dev/null | awk '/Number of entries/ {print}' || echo "ipset yok"

if [[ "$MODE" == "ban" ]]; then
  echo ""
  echo "=== BAN: stick-table conn>=3 (top ${N}) ==="
  awk '$2 >= 3 { print $2, $3 }' "$TABLE_FILE" | sort -nr | head -n "$N" | while read -r conn ip; do
    ban_one "$ip" "conn=$conn" || true
  done

  echo ""
  echo "=== BAN: Redis bs:ip_hits top ${N} ==="
  "${COMPOSE[@]}" exec -T redis redis-cli ZREVRANGE bs:ip_hits 0 $((N - 1)) 2>/dev/null | tr -d '\r' \
    | while read -r ip; do
        [[ -z "$ip" ]] && continue
        # WITHSCORES yok — sadece member; cift satir skor degil
        ban_one "$ip" "hits" || true
      done

  echo ""
  echo "=== ipset sonra ==="
  ipset list bs_banned 2>/dev/null | awk '/Number of entries/ {print}' || true
fi

echo ""
echo "Watcher esik kontrol: docker compose exec watcher printenv BAN_THRESHOLD"
echo "300 olmali; 1000 ise: docker compose up -d --force-recreate watcher"
echo "Toplu: bash scripts/top-attackers.sh 200 ban"
