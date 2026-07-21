#!/usr/bin/env bash
# Ban listesinde (ipset / Redis) trusted bot IP araligi var mi?
#
# Not: trusted_bots engine pipeline'da muaf; watcher/ipset hit ban'i bot CIDR kontrol etmez.
#
# Kullanim (sunucuda /opt/badsector):
#   bash scripts/check-banned-bots.sh
#   bash scripts/check-banned-bots.sh --redis-only
#   bash scripts/check-banned-bots.sh --unban    # eslesen bot IP'lerini ac

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IPSET_NAME="${IPSET_NAME:-bs_banned}"
BOTS_JSON="${BADSECTOR_BOTS_PATH:-$ROOT/data/bots}/bot-ranges.json"
COMPOSE=(docker compose)
FROM_IPSET=true
FROM_REDIS=true
DO_UNBAN=false
LIMIT=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ipset-only) FROM_REDIS=false; shift ;;
    --redis-only) FROM_IPSET=false; shift ;;
    --unban) DO_UNBAN=true; shift ;;
    --limit) LIMIT="${2:-50}"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Bilinmeyen arguman: $1" >&2; exit 1 ;;
  esac
done

redis_cli() {
  "${COMPOSE[@]}" exec -T redis redis-cli "$@" </dev/null 2>/dev/null || true
}

TMP=$(mktemp)
trap 'rm -f "$TMP" "${TMP}.ips"' EXIT

{
  if $FROM_IPSET && command -v ipset >/dev/null 2>&1; then
    ipset list "$IPSET_NAME" 2>/dev/null | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1}' || true
  fi
  if $FROM_REDIS; then
    redis_cli --scan --pattern 'bs:ban:*' 2>/dev/null | sed 's|^bs:ban:||' || true
  fi
} | sort -u > "${TMP}.ips"

TOTAL=$(wc -l < "${TMP}.ips" | tr -d ' ')
if [[ "$TOTAL" -eq 0 ]]; then
  echo "Ban listesi bos (ipset=$FROM_IPSET redis=$FROM_REDIS)."
  exit 0
fi

if [[ ! -f "$BOTS_JSON" ]]; then
  echo "WARN: $BOTS_JSON yok — worker indirmeli veya: bash scripts/download-bots.sh" >&2
fi

python3 - "$BOTS_JSON" "${TMP}.ips" "$LIMIT" "$DO_UNBAN" "$IPSET_NAME" "$ROOT" <<'PY'
import ipaddress
import json
import os
import subprocess
import sys

bots_json, ips_file, limit_s, unban_s, ipset_name, root = sys.argv[1:7]
limit = int(limit_s)
do_unban = unban_s.lower() == "true"

# Statik prefix (bot-ranges.json eksik / Yandex / DuckDuckBot)
STATIC = {
    "Googlebot(static)": ["66.249."],
    "Bingbot(static)": ["157.55.", "207.46.", "40.77.", "13.66.", "13.67."],
    "YandexBot": ["5.255.", "87.250.", "95.108.", "100.43.", "141.8."],
    "DuckDuckBot": ["40.88.", "52.149.", "54.208."],
}

networks = []  # (bot_name, network)
if os.path.isfile(bots_json):
    with open(bots_json, encoding="utf-8") as f:
        data = json.load(f)
    for bot, cidrs in (data.get("bots") or {}).items():
        for cidr in cidrs:
            try:
                networks.append((bot, ipaddress.ip_network(cidr, strict=False)))
            except ValueError:
                pass

with open(ips_file, encoding="utf-8") as f:
    ips = [ln.strip() for ln in f if ln.strip()]

def static_match(ip: str):
    for bot, prefixes in STATIC.items():
        for p in prefixes:
            if ip.startswith(p):
                return bot
    return None

def cidr_match(ip: str):
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return None
    for bot, net in networks:
        if addr in net:
            return bot
    return None

hits = []
for ip in ips:
    bot = cidr_match(ip) or static_match(ip)
    if bot:
        hits.append((ip, bot))

print(f"=== Ban listesi: {len(ips)} benzersiz IP ===")
print(f"=== Bot aralik dosyasi: {bots_json} ({len(networks)} CIDR) ===")
print(f"=== Bot araliginda banli IP: {len(hits)} ===")
if not hits:
    print("Eslesme yok — ban listesinde bilinen bot araligi gorunmuyor.")
    sys.exit(0)

by_bot = {}
for ip, bot in hits:
    by_bot.setdefault(bot, []).append(ip)

print("\n--- Bot basina ---")
for bot in sorted(by_bot, key=lambda b: (-len(by_bot[b]), b)):
    print(f"  {bot}: {len(by_bot[bot])} IP")

print(f"\n--- Ornek (max {limit}) ---")
for ip, bot in hits[:limit]:
    print(f"  {ip}  ->  {bot}")
if len(hits) > limit:
    print(f"  ... +{len(hits) - limit} daha")

print("\nTek IP ac: sudo ./scripts/clear-bans.sh <IP>")
print("Toplu ac:  bash scripts/check-banned-bots.sh --unban")

if do_unban:
    clear_sh = os.path.join(root, "scripts", "clear-bans.sh")
    print("\n=== UNBAN (bot IP) ===")
    for ip, bot in hits:
        print(f"unban {ip} ({bot})")
        subprocess.run(["bash", clear_sh, ip], check=False)
PY
