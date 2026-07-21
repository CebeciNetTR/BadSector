#!/usr/bin/env bash
# BadSector — OVH Network Firewall icin IP/CIDR listesi uret.
#
# OVH edge firewall'da tek tek 5000 IP kurali pratik degil; oncelik:
#   - Tekrarlayan /24 bloklari (min N IP ayni subnet)
#   - En gurultulu tekil IP'ler (OVH kural limitine sigacak kadar)
#
# Kullanim (sunucu, root/sudo):
#   bash scripts/export-ovh-blocklist.sh
#   bash scripts/export-ovh-blocklist.sh --min-subnet 5 --top 30
#   bash scripts/export-ovh-blocklist.sh --from-ipset --from-redis
#
# Cikti: /tmp/ovh-blocklist-*.txt (OVH paneline elle veya API)

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MIN_SUBNET=3
TOP_SINGLE=50
FROM_IPSET=true
FROM_REDIS=true
FROM_HITS=true
OUT_DIR="/tmp"

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
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

COMPOSE=(docker compose)
if ! docker info &>/dev/null 2>&1; then
  COMPOSE=(sudo docker compose)
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

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

TS=$(date +%Y%m%d-%H%M%S)
ALL="${OUT_DIR}/ovh-blocklist-all-${TS}.txt"
SUBNETS="${OUT_DIR}/ovh-blocklist-subnets-${TS}.txt"
TOP="${OUT_DIR}/ovh-blocklist-top-${TS}.txt"
OVH_RULES="${OUT_DIR}/ovh-firewall-hints-${TS}.txt"

cp "$TMP" "$ALL"

# /24 agregasyon: a.b.c.x -> a.b.c.0/24
awk -F. '{print $1"."$2"."$3".0/24"}' "$TMP" | sort | uniq -c | sort -rn \
  | awk -v m="$MIN_SUBNET" '$1 >= m {print $2, "("$1" IP)"}' > "$SUBNETS"

head -n "$TOP_SINGLE" "$TMP" > "$TOP"

{
  echo "# BadSector OVH Network Firewall — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Toplam benzersiz IP: $COUNT"
  echo "#"
  echo "# OVH: Public Cloud / Bare Metal → IP → Network Firewall (edge, VAC oncesi)"
  echo "#   Action: Deny | Protocol: TCP | Dest port: 443 (ve gerekirse 80)"
  echo "#   Source: asagidaki CIDR veya IP"
  echo "#"
  echo "# ONERI: Once /24 subnet kurallari (asagida), limit dolunca top tekil IP."
  echo "# OVH kural limiti dusuk olabilir (~20-30); /24 ile yuzlerce IP tek kuralda."
  echo "#"
  echo "# --- /24 subnet onceligi (min ${MIN_SUBNET} IP ayni blok) ---"
  cat "$SUBNETS"
  echo "#"
  echo "# --- Top ${TOP_SINGLE} tekil IP ---"
  cat "$TOP"
} > "$OVH_RULES"

echo "=== Export tamam ==="
echo "  Tum IP'ler ($COUNT):     $ALL"
echo "  /24 subnet onceligi:     $SUBNETS"
echo "  Top tekil IP:            $TOP"
echo "  OVH panel notlari:       $OVH_RULES"
echo ""
echo "Subnet ornegi (ilk 5):"
head -5 "$SUBNETS"
echo ""
echo "OVH panel: IP → Network Firewall → Add rule → Deny TCP 443 from source CIDR"
