#!/usr/bin/env bash
# BadSector — OVH Network Firewall icin IP/CIDR listesi (GeoIP: TR haric).
#
# Varsayilan: sadece geo != TR olanlar OVH export'una girer.
# TR IP'ler ayri dosyada + ozet logda gorunur (OVH'ye koyma).
#
# Kullanim (sunucu, root/sudo):
#   bash scripts/export-ovh-blocklist.sh
#   bash scripts/export-ovh-blocklist.sh --min-subnet 5 --top 30
#   bash scripts/export-ovh-blocklist.sh --include-tr   # TR'yi de OVH listesine ekle (tavsiye edilmez)
#
# Gereksinim: data/geoip/GeoLite2-Country.mmdb
#   python3 -m pip install maxminddb   VEYA   apt install maxminddb-tools

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MIN_SUBNET=3
TOP_SINGLE=50
FROM_IPSET=true
FROM_REDIS=true
FROM_HITS=true
OUT_DIR="/tmp"
KEEP_COUNTRY="TR"
ONLY_NON_TR=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-subnet) MIN_SUBNET="$2"; shift 2 ;;
    --top) TOP_SINGLE="$2"; shift 2 ;;
    --from-ipset) FROM_IPSET=true; shift ;;
    --no-ipset) FROM_IPSET=false; shift ;;
    --from-redis) FROM_REDIS=true; shift ;;
    --no-redis) FROM_REDIS=false; shift ;;
    --from-hits) FROM_HITS=true; shift ;;
    --no-hits) FROM_HITS=false; shift ;;
    --include-tr) ONLY_NON_TR=false; shift ;;
    --keep-country) KEEP_COUNTRY="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0"
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

TMP=$(mktemp)
GEO=$(mktemp)
trap 'rm -f "$TMP" "$GEO"' EXIT

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
  "${COMPOSE[@]}" exec -T redis redis-cli ZREVRANGE bs:ip_hits 0 499 </dev/null 2>/dev/null \
    | collect_ip >> "$TMP" || true
fi

sort -u "$TMP" -o "$TMP"
COUNT=$(wc -l < "$TMP" | tr -d ' ')
if [[ "$COUNT" -eq 0 ]]; then
  echo "IP bulunamadi (ipset/redis bos veya docker yetkisi yok)" >&2
  exit 1
fi

echo "=== GeoIP lookup ($COUNT IP) ==="
if ! python3 "${ROOT}/scripts/geoip-lookup-batch.py" "$GEOIP_DB" < "$TMP" > "$GEO" 2>/dev/null; then
  if command -v mmdblookup &>/dev/null; then
    : > "$GEO"
    while IFS= read -r ip; do
      cc=$(mmdblookup -f "$GEOIP_DB" --ip "$ip" country iso_code 2>/dev/null \
        | awk -F'"' '/iso_code/ {print $2; exit}' | tr '[:lower:]' '[:upper:]')
      [[ -z "$cc" ]] && cc="??"
      printf '%s\t%s\n' "$ip" "$cc"
    done < "$TMP" > "$GEO"
  else
    echo "HATA: python3 maxminddb veya mmdblookup gerekli:" >&2
    echo "  pip install maxminddb   |   apt install maxminddb-tools" >&2
    exit 1
  fi
fi

TS=$(date +%Y%m%d-%H%M%S)
ALL="${OUT_DIR}/ovh-blocklist-all-${TS}.txt"
GEO_ALL="${OUT_DIR}/ovh-blocklist-geo-${TS}.txt"
TR_LIST="${OUT_DIR}/ovh-blocklist-TR-${TS}.txt"
NONTR_LIST="${OUT_DIR}/ovh-blocklist-non-TR-${TS}.txt"
SUBNETS="${OUT_DIR}/ovh-blocklist-subnets-non-TR-${TS}.txt"
TOP="${OUT_DIR}/ovh-blocklist-top-non-TR-${TS}.txt"
OVH_RULES="${OUT_DIR}/ovh-firewall-hints-${TS}.txt"

cp "$TMP" "$ALL"

# ip + cc dosyalari
: > "$GEO_ALL"
: > "$TR_LIST"
: > "$NONTR_LIST"
while IFS=$'\t' read -r ip cc; do
  [[ -z "$ip" ]] && continue
  cc="${cc^^}"
  [[ -z "$cc" ]] && cc="??"
  echo "$ip $cc" >> "$GEO_ALL"
  if [[ "$cc" == "$KEEP_COUNTRY" ]]; then
    echo "$ip" >> "$TR_LIST"
  else
    echo "$ip" >> "$NONTR_LIST"
  fi
done < "$GEO"

TR_COUNT=$(wc -l < "$TR_LIST" 2>/dev/null | tr -d ' ' || echo 0)
NONTR_COUNT=$(wc -l < "$NONTR_LIST" 2>/dev/null | tr -d ' ' || echo 0)

echo ""
echo "=== Ulke ozeti (top 15) ==="
awk '{print $2}' "$GEO_ALL" | sort | uniq -c | sort -rn | head -15 \
  | awk '{printf "  geo=%s  %s IP\n", $2, $1}'

echo ""
echo "=== TR (OVH'ye KOYMA — $TR_COUNT IP) ==="
if [[ "$TR_COUNT" -gt 0 ]]; then
  awk '$2=="TR" {printf "  geo=TR  %s\n", $1}' "$GEO_ALL" | head -20
  if [[ "$TR_COUNT" -gt 20 ]]; then
    echo "  ... +$((TR_COUNT - 20)) daha → $TR_LIST"
  fi
else
  echo "  (yok)"
fi

echo ""
echo "=== non-TR OVH adaylari ($NONTR_COUNT IP) ==="

EXPORT_SRC="$NONTR_LIST"
if ! $ONLY_NON_TR; then
  EXPORT_SRC="$ALL"
  echo "  (--include-tr: tum IP'ler export'ta)"
fi

# /24: sadece non-TR export; subnet icinde TR varsa SKIP
awk -v min="$MIN_SUBNET" '
  NR==FNR { split($1,a,"."); geo[$1]=$2; next }
  {
    ip=$1; cc=geo[ip]; if (cc=="") cc="??"
    split(ip,a,"."); s=a[1]"."a[2]"."a[3]".0/24"
    n[s]++; if (cc=="TR") tr[s]++; c[s","cc]++
  }
  END {
    for (s in n) {
      if (n[s] < min) continue
      if (tr[s] > 0) {
        printf "# SKIP %s (%d IP) — icinde %d geo=TR\n", s, n[s], tr[s]
        next
      }
      tops=""
      for (k in c) {
        split(k, p, SUBSEP); if (p[1]!=s) continue
        tops = tops p[2]":" c[k] " "
      }
      printf "%s (%d IP) geo=%s\n", s, n[s], tops
    }
  }
' "$GEO_ALL" "$EXPORT_SRC" | sort -t'(' -k2 -rn > "$SUBNETS"

head -n "$TOP_SINGLE" "$EXPORT_SRC" | while read -r ip; do
  cc=$(awk -v ip="$ip" '$1==ip {print $2; exit}' "$GEO_ALL")
  echo "$ip geo=$cc"
done > "$TOP"

{
  echo "# BadSector OVH Network Firewall — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Toplam IP: $COUNT | geo=$KEEP_COUNTRY: $TR_COUNT (OVH'ye ekleme) | non-$KEEP_COUNTRY: $NONTR_COUNT"
  echo "#"
  echo "# OVH: IP → Network Firewall → Deny TCP 443 (source CIDR)"
  echo "# Sadece non-$KEEP_COUNTRY subnet'ler (TR iceren /24 atlandi)"
  echo "#"
  echo "# --- /24 non-$KEEP_COUNTRY (min $MIN_SUBNET IP, TR yok) ---"
  grep -v '^#' "$SUBNETS" || true
  echo "#"
  echo "# --- Atlanan (subnet icinde TR) ---"
  grep '^# SKIP' "$SUBNETS" || echo "# (yok)"
  echo "#"
  echo "# --- Top $TOP_SINGLE tekil non-$KEEP_COUNTRY ---"
  cat "$TOP"
  echo "#"
  echo "# --- geo=TR ornek (banlama) ---"
  awk '$2=="TR" || $2=="tr" {print "geo=TR", $1}' "$GEO_ALL" | head -30
} > "$OVH_RULES"

echo ""
echo "=== Export tamam ==="
echo "  Tum IP + geo:          $GEO_ALL"
echo "  geo=$KEEP_COUNTRY (OVH disi):       $TR_LIST ($TR_COUNT)"
echo "  non-$KEEP_COUNTRY OVH:             $NONTR_LIST ($NONTR_COUNT)"
echo "  Subnet non-$KEEP_COUNTRY:          $SUBNETS"
echo "  Top non-$KEEP_COUNTRY:             $TOP"
echo "  Panel notlari:         $OVH_RULES"
echo ""
echo "OVH'ye ekle (ilk subnet'ler):"
grep -v '^#' "$SUBNETS" | head -10 | awk '{print "  Deny TCP 443 from", $1}'
