#!/usr/bin/env bash
# BadSector — en gurultulu IP'leri goster (OVH firewall icin).
#
# ONEMLI: ipset (kernel) banli IP paketleri HAProxy'ye ULASMAZ → hit sayilmaz.
# Bu script "hala edge'e gelen" / "ban oncesi biriken" top konusmacilari gosterir.
#
# Kullanim (sunucu /opt/badsector):
#   bash scripts/top-attackers.sh          # ozet
#   bash scripts/top-attackers.sh 30       # her listede top N (varsayilan 20)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
N="${1:-20}"
COMPOSE=(docker compose)
SOCK=/var/run/haproxy/admin.sock

haproxy_cmd() {
  echo "$1" | "${COMPOSE[@]}" exec -T haproxy socat stdio "${SOCK}" 2>/dev/null || true
}

parse_table() {
  # portable: key=IP ... http_req_rate=N conn_cur=N
  haproxy_cmd "show table fe_https" | sed 's/[, ]/\n/g' | awk '
    BEGIN { ip=""; rate=0; conn=0 }
    /^key=/ { if (ip != "") print rate, conn, ip; ip=substr($0,5); rate=0; conn=0; next }
    /^http_req_rate=/ { rate=substr($0,15)+0; next }
    /^conn_cur=/ { conn=substr($0,10)+0; next }
    END { if (ip != "") print rate, conn, ip }
  '
}

echo "=== Redis bs:ip_hits (kumulatif, ban olunca ZREM — kernel banli YOK) top ${N} ==="
"${COMPOSE[@]}" exec -T redis redis-cli ZREVRANGE bs:ip_hits 0 $((N - 1)) WITHSCORES 2>/dev/null | tr -d '\r' || true

echo ""
echo "=== HAProxy stick-table http_req_rate/10s (canli, TLS+HTTP gecen) ==="
parse_table | sort -nr -k1,1 | head -n "$N" | awk '{printf "rate=%s/10s conn=%s  %s\n", $1, $2, $3}'

echo ""
echo "=== HAProxy stick-table conn_cur (eszamanli baglanti) top ${N} ==="
parse_table | sort -nr -k2,2 | head -n "$N" | awk '{printf "conn=%s rate=%s/10s  %s\n", $2, $1, $3}'

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
echo "=== ipset boyutu (kernel ban — bunlar hit SAYILMAZ) ==="
ipset list bs_banned 2>/dev/null | awk '/Number of entries/ {print}' || echo "ipset yok"

echo ""
echo "OVH'ye: stick-table / ss listesindeki IP'leri Network Firewall'a ekle."
echo "Tek IP ipset:  sudo ipset add bs_banned IP timeout 7200 -exist"
