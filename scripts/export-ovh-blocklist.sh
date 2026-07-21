#!/usr/bin/env bash
# BadSector — OVH raporu: top IP + ASN ozeti (subnet/ASN engeli panelde YOK).
#
# OVH Edge Firewall: sadece tekil Source IP (+ TCP 443). ASN/CIDR panel kabul etmez.
# ASN raporu: hangi ag saldiriyor → OVH ticket / ipset (sunucuda zaten var).
#
# Kullanim:
#   bash scripts/export-ovh-blocklist.sh
#   bash scripts/export-ovh-blocklist.sh --ovh-top 20 --min-subnet-asn 10

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OVH_TOP=20
TOP_SINGLE=50
MIN_SUBNET_ASN=10
FROM_IPSET=true
FROM_REDIS=true
FROM_HITS=true
OUT_DIR="/tmp"
KEEP_COUNTRY="TR"
ONLY_NON_TR=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ovh-top) OVH_TOP="$2"; shift 2 ;;
    --top) TOP_SINGLE="$2"; shift 2 ;;
    --min-subnet-asn) MIN_SUBNET_ASN="$2"; shift 2 ;;
    --from-ipset) FROM_IPSET=true; shift ;;
    --no-ipset) FROM_IPSET=false; shift ;;
    --from-redis) FROM_REDIS=true; shift ;;
    --no-redis) FROM_REDIS=false; shift ;;
    --from-hits) FROM_HITS=true; shift ;;
    --no-hits) FROM_HITS=false; shift ;;
    --include-tr) ONLY_NON_TR=false; shift ;;
    --keep-country) KEEP_COUNTRY="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      echo "  --ovh-top N          OVH panele tekil IP (varsayilan 20)"
      echo "  --min-subnet-asn N   ASN/subnet raporu esigi (varsayilan 10 IP)"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

for f in "${ROOT}/data/geoip/GeoLite2-Country.mmdb" "${ROOT}/data/geoip/GeoLite2-ASN.mmdb"; do
  if [[ ! -f "$f" ]]; then
    echo "HATA: $f yok. bash scripts/download-geoip.sh" >&2
    exit 1
  fi
done

COMPOSE=(docker compose)
if ! docker info &>/dev/null 2>&1; then
  COMPOSE=(sudo docker compose)
fi

GEO_FULL="/etc/badsector/scripts/geoip-lookup-batch-full.lua"

TMP=$(mktemp)
GEO=$(mktemp)
HITS=$(mktemp)
FULL="${OUT_DIR}/ovh-full-$$.txt"
trap 'rm -f "$TMP" "$GEO" "$HITS" "$FULL"' EXIT

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

echo "=== GeoIP+ASN lookup ($COUNT IP) — BadSector MMDB ==="
if ! "${COMPOSE[@]}" exec -T engine /usr/local/openresty/bin/resty "$GEO_FULL" < "$TMP" > "$GEO" 2>/dev/null; then
  echo "HATA: engine lookup basarisiz (docker compose up -d engine)" >&2
  exit 1
fi

"${COMPOSE[@]}" exec -T redis redis-cli ZREVRANGE bs:ip_hits 0 -1 WITHSCORES </dev/null 2>/dev/null \
  | tr -d '\r' > "$HITS" || true

TS=$(date +%Y%m%d-%H%M%S)
GEO_ALL="${OUT_DIR}/ovh-blocklist-geo-${TS}.txt"
TR_LIST="${OUT_DIR}/ovh-blocklist-TR-${TS}.txt"
OVH_IPS="${OUT_DIR}/ovh-top-ips-${TS}.txt"
OVH_DETAIL="${OUT_DIR}/ovh-top-ips-${TS}.detail.txt"
ASN_TOP="${OUT_DIR}/ovh-asn-top-${TS}.txt"
SUBNET_ASN="${OUT_DIR}/ovh-subnet-asn-${TS}.txt"
US_ASN="${OUT_DIR}/ovh-asn-US-${TS}.txt"

: > "$GEO_ALL"
: > "$TR_LIST"
while IFS=$'\t' read -r ip cc asn org; do
  [[ -z "$ip" ]] && continue
  cc="${cc^^}"
  [[ -z "$cc" ]] && cc="??"
  [[ -z "$asn" ]] && asn="?"
  echo "$ip $cc AS${asn} ${org}" >> "$GEO_ALL"
  [[ "$cc" == "$KEEP_COUNTRY" ]] && echo "$ip" >> "$TR_LIST"
done < "$GEO"

TR_COUNT=$(wc -l < "$TR_LIST" 2>/dev/null | tr -d ' ' || echo 0)

# OVH top IP (non-TR, hit sirasi)
awk -v keep="$KEEP_COUNTRY" -v only_nontr="$ONLY_NON_TR" '
  NR==FNR {
    if (NR % 2 == 1) { hold=$1; next }
    hits[hold]=$1+0; next
  }
  { cc=$2; asn=$3; org=""; for(i=4;i<=NF;i++) org=org (i>4?" ":"") $i
    geo[$1]=cc "\t" asn "\t" org }
  END {
    for (ip in geo) {
      split(geo[ip], p, "\t"); cc=p[1]
      if (only_nontr == "true" && cc == keep) next
      sc=(ip in hits) ? hits[ip] : 0
      printf "%d\t%s\t%s\t%s\t%s\n", sc, ip, cc, p[2], p[3]
    }
  }
' "$HITS" "$GEO_ALL" | sort -t$'\t' -k1,1rn > "$OVH_DETAIL"

head -n "$OVH_TOP" "$OVH_DETAIL" | awk -F'\t' '{print $2}' > "$OVH_IPS"

# Top ASN (non-TR, tum liste)
awk -v keep="$KEEP_COUNTRY" '
  {
    cc=$2; asn=$3; org=""; for(i=4;i<=NF;i++) org=org (i>4?" ":"") $i
    if (cc==keep) next
    if (asn=="" || asn=="AS?") next
    n[asn]++; orgn[asn]=org; ccn[asn]=cc
  }
  END {
    for (a in n) printf "%d\t%s\t%s\t%s\n", n[a], a, ccn[a], orgn[a]
  }
' "$GEO_ALL" | sort -t$'\t' -k1,1rn > "$ASN_TOP"

# US ASN dagilimi
awk '$2=="US" { asn=$3; org=""; for(i=4;i<=NF;i++) org=org (i>4?" ":"") $i; n[asn]++; o[asn]=org }
  END { for(a in n) printf "%d\t%s\t%s\n", n[a], a, o[a] }' "$GEO_ALL" | sort -t$'\t' -k1,1rn > "$US_ASN"

# Subnet >= MIN_SUBNET_ASN IP: baskin ASN
awk -v min="$MIN_SUBNET_ASN" -v keep="$KEEP_COUNTRY" '
  {
    ip=$1; cc=$2; asn=$3; org=""; for(i=4;i<=NF;i++) org=org (i>4?" ":"") $i
    split(ip,a,"."); s=a[1]"."a[2]"."a[3]".0/24"
    sn[s]++
    if (cc==keep) { tr[s]++; next }
    if (asn!="" && asn!="AS?") { an[s SUBSEP asn]++; if (!orgs[s SUBSEP asn]) orgs[s SUBSEP asn]=org }
    gc[s SUBSEP cc]++
  }
  END {
    for (s in sn) {
      if (sn[s] < min) continue
      if (tr[s] > 0) { printf "# SKIP %s (%d IP) — icinde %d geo=TR\n", s, sn[s], tr[s]; continue }
      best_asn="?"; best_n=0; best_org=""
      for (k in an) {
        split(k,p,SUBSEP); if (p[1]!=s) continue
        if (an[k]>best_n) { best_n=an[k]; best_asn=p[2]; best_org=orgs[k] }
      }
      tops=""
      for (k in gc) { split(k,p,SUBSEP); if (p[1]!=s) continue; tops=tops p[2]":" gc[k] " " }
      printf "%s (%d IP) dominant=%s %s (%d/%d) countries=%s\n", s, sn[s], best_asn, best_org, best_n, sn[s]-tr[s], tops
    }
  }
' "$GEO_ALL" | sort -t'(' -k2 -rn > "$SUBNET_ASN"

echo ""
echo "=== Ulke ozeti (top 10) ==="
awk '{print $2}' "$GEO_ALL" | sort | uniq -c | sort -rn | head -10 \
  | awk '{printf "  geo=%s  %s IP\n", $2, $1}'

echo ""
echo "=== Top ASN (non-TR, tum ban listesi) ==="
echo "  NOT: OVH Edge Firewall ASN kurali DESTEKLEMEZ — sadece tekil Source IP."
echo "  ASN raporu: OVH ticket / VAC icin; gercek engel sunucuda ipset."
awk -F'\t' 'NR<=15 {printf "  %3d IP  %s  geo=%s  %s\n", $1, $2, $3, $4}' "$ASN_TOP"

echo ""
echo "=== geo=US — hangi ASN? (top 10) ==="
awk -F'\t' 'NR<=10 {printf "  %3d IP  %s  %s\n", $1, $2, $3}' "$US_ASN"

echo ""
echo "=== Subnet >= ${MIN_SUBNET_ASN} IP — baskin ASN ==="
grep -v '^# SKIP' "$SUBNET_ASN" | head -15
skip_n=$(grep -c '^# SKIP' "$SUBNET_ASN" 2>/dev/null || echo 0)
[[ "$skip_n" -gt 0 ]] && echo "  (${skip_n} subnet TR icerdigi icin atlandi)"

echo ""
echo "=== OVH top $OVH_TOP tekil IP (panel) ==="
awk -F'\t' -v n="$OVH_TOP" 'NR<=n {printf "  %2d. %s  hits=%s geo=%s %s\n", NR, $2, $1, $3, $4}' "$OVH_DETAIL"

echo ""
echo "=== Dosyalar ==="
echo "  ASN top:        $ASN_TOP"
echo "  ASN geo=US:     $US_ASN"
echo "  Subnet+ASN:     $SUBNET_ASN"
echo "  OVH IP list:    $OVH_IPS"
echo "  Detay:          $OVH_DETAIL"
