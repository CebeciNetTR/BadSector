#!/usr/bin/env bash
# BadSector — OVH Edge Firewall: top saldirgan IP (tek tek, subnet YOK).
#
# OVH paneli /24 kabul etmez; max ~20 kural. non-TR + bs:ip_hits siralamasina gore top N.
# GeoIP: BadSector ile ayni MMDB + engine geo_lookup.
#
# Kullanim:
#   bash scripts/export-ovh-blocklist.sh              # top 20 non-TR (OVH icin)
#   bash scripts/export-ovh-blocklist.sh --ovh-top 15
#   bash scripts/export-ovh-blocklist.sh --top 100    # uzun rapor dosyasi

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OVH_TOP=20
TOP_SINGLE=50
FROM_IPSET=true
FROM_REDIS=true
FROM_HITS=true
OUT_DIR="/tmp"
KEEP_COUNTRY="TR"
ONLY_NON_TR=true
WITH_SUBNETS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ovh-top) OVH_TOP="$2"; shift 2 ;;
    --top) TOP_SINGLE="$2"; shift 2 ;;
    --subnets) WITH_SUBNETS=true; shift ;;
    --from-ipset) FROM_IPSET=true; shift ;;
    --no-ipset) FROM_IPSET=false; shift ;;
    --from-redis) FROM_REDIS=true; shift ;;
    --no-redis) FROM_REDIS=false; shift ;;
    --from-hits) FROM_HITS=true; shift ;;
    --no-hits) FROM_HITS=false; shift ;;
    --include-tr) ONLY_NON_TR=false; shift ;;
    --keep-country) KEEP_COUNTRY="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      echo "  --ovh-top N   OVH panele eklenecek tekil IP (varsayilan 20)"
      echo "  --subnets     /24 rapor dosyasi da uret (panel icin degil)"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

GEOIP_DB="${ROOT}/data/geoip/GeoLite2-Country.mmdb"
if [[ ! -f "$GEOIP_DB" ]]; then
  echo "HATA: $GEOIP_DB yok. bash scripts/download-geoip.sh" >&2
  exit 1
fi

COMPOSE=(docker compose)
if ! docker info &>/dev/null 2>&1; then
  COMPOSE=(sudo docker compose)
fi

GEO_LOOKUP_SCRIPT="/etc/badsector/scripts/geoip-lookup-batch.lua"

TMP=$(mktemp)
GEO=$(mktemp)
HITS=$(mktemp)
trap 'rm -f "$TMP" "$GEO" "$HITS"' EXIT

collect_ip() {
  grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true
}

if $FROM_IPSET && command -v ipset &>/dev/null; then
  ipset list bs_banned 2>/dev/null | awk '/^[0-9]/ {print $1}' | collect_ip >> "$TMP" || true
fi

if $FROM_REDIS; then
  "${COMPOSE[@]}" exec -T redis redis-cli --scan --pattern 'bs:ban:*' </dev/null 2>/dev/null \
    | sed 's/^bs:ban://' | collect_ip >> "$TMP" || true
fi

if $FROM_HITS; then
  "${COMPOSE[@]}" exec -T redis redis-cli ZREVRANGE bs:ip_hits 0 999 </dev/null 2>/dev/null \
    | collect_ip >> "$TMP" || true
fi

sort -u "$TMP" -o "$TMP"
COUNT=$(wc -l < "$TMP" | tr -d ' ')
if [[ "$COUNT" -eq 0 ]]; then
  echo "IP bulunamadi" >&2
  exit 1
fi

echo "=== GeoIP lookup ($COUNT IP) — BadSector MMDB ==="
if ! "${COMPOSE[@]}" exec -T engine /usr/local/openresty/bin/resty "$GEO_LOOKUP_SCRIPT" < "$TMP" > "$GEO" 2>/dev/null; then
  echo "HATA: engine geo lookup basarisiz (docker compose up -d engine)" >&2
  exit 1
fi

# bs:ip_hits skorlari (istek sayaci)
"${COMPOSE[@]}" exec -T redis redis-cli ZREVRANGE bs:ip_hits 0 -1 WITHSCORES </dev/null 2>/dev/null \
  | tr -d '\r' > "$HITS" || true

TS=$(date +%Y%m%d-%H%M%S)
GEO_ALL="${OUT_DIR}/ovh-blocklist-geo-${TS}.txt"
TR_LIST="${OUT_DIR}/ovh-blocklist-TR-${TS}.txt"
OVH_IPS="${OUT_DIR}/ovh-top-ips-${TS}.txt"
OVH_DETAIL="${OUT_DIR}/ovh-top-ips-${TS}.detail.txt"
TOP_REPORT="${OUT_DIR}/ovh-top-report-${TS}.txt"

: > "$GEO_ALL"
: > "$TR_LIST"
while IFS=$'\t' read -r ip cc; do
  [[ -z "$ip" ]] && continue
  cc="${cc^^}"
  [[ -z "$cc" ]] && cc="??"
  echo "$ip $cc" >> "$GEO_ALL"
  [[ "$cc" == "$KEEP_COUNTRY" ]] && echo "$ip" >> "$TR_LIST"
done < "$GEO"

TR_COUNT=$(wc -l < "$TR_LIST" 2>/dev/null | tr -d ' ' || echo 0)

# non-TR + hit skoruna gore sirala → OVH top N
awk -v keep="$KEEP_COUNTRY" -v only_nontr="$ONLY_NON_TR" '
  NR==FNR {
    if (NR % 2 == 1) { hold=$1; next }
    hits[hold]=$1+0
    next
  }
  { geo[$1]=$2 }
  END {
    for (ip in geo) {
      cc=geo[ip]
      if (only_nontr == "true" && cc == keep) next
      sc=(ip in hits) ? hits[ip] : 0
      printf "%d\t%s\t%s\n", sc, ip, cc
    }
  }
' "$HITS" "$GEO_ALL" | sort -t$'\t' -k1,1rn > "$OVH_DETAIL"

head -n "$OVH_TOP" "$OVH_DETAIL" | awk -F'\t' '{print $2}' > "$OVH_IPS"
head -n "$TOP_SINGLE" "$OVH_DETAIL" > "$TOP_REPORT"

echo ""
echo "=== Ulke ozeti (top 10) ==="
awk '{print $2}' "$GEO_ALL" | sort | uniq -c | sort -rn | head -10 \
  | awk '{printf "  geo=%s  %s IP\n", $2, $1}'

echo ""
echo "=== geo=TR — OVH'ye KOYMA ($TR_COUNT IP) ==="
awk '$2=="TR" {printf "  geo=TR  %s\n", $1}' "$GEO_ALL" | head -10
[[ "$TR_COUNT" -gt 10 ]] && echo "  ... → $TR_LIST"

echo ""
echo "=== OVH top $OVH_TOP (tek IP, hit sirasi, non-TR) ==="
awk -F'\t' '{printf "  hits=%s  %s  geo=%s\n", $1, $2, $3}' "$OVH_DETAIL" | head -n "$OVH_TOP"

echo ""
echo "=== OVH panele kopyala (her biri ayri kural) ==="
echo "  Mode: Refuse | Protocol: TCP | Dest port: 443 | Source IP: <asagidaki>"
echo "  TCP status: None"
awk -F'\t' -v n="$OVH_TOP" 'NR<=n {printf "  %2d. %s   (hits=%s geo=%s)\n", NR, $2, $1, $3}' "$OVH_DETAIL"

echo ""
echo "=== Dosyalar ==="
echo "  OVH tek IP listesi:  $OVH_IPS"
echo "  Detay (hit+geo):     $OVH_DETAIL"
echo "  Tum IP+geo:          $GEO_ALL"
echo "  geo=TR:              $TR_LIST"

if $WITH_SUBNETS; then
  SUBNETS="${OUT_DIR}/ovh-subnets-${TS}.txt"
  awk -v min=3 '
    { ip=$1; cc=$2; split(ip,a,"."); s=a[1]"."a[2]"."a[3]".0/24"
      if (cc=="TR") tr[s]++; else { nontr[s]++; nh[s SUBSEP ip]=1 }
    }
    END {
      for (s in nontr) {
        if (tr[s]>0) next
        if (nontr[s]<min) next
        print s, "(" nontr[s] " IP)"
      }
    }
  ' "$GEO_ALL" | sort -k2 -rn > "$SUBNETS"
  echo "  Subnet rapor:        $SUBNETS"
fi

echo ""
echo "Sunucuda zaten ipset var — OVH kurallari edge katmani (TLS oncesi ek koruma)."
