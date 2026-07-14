#!/usr/bin/env bash
# Resmi bot IP aralik listelerini (Googlebot + Bingbot) indirip engine'in
# okudugu data/bots/bot-ranges.json dosyasini uretir.
#
# Not: badsector-worker bunu zaten gunluk otomatik yapar. Bu script yalnizca
# worker calismadan once elle tohumlamak (ya da worker'siz kurulum) icindir.
# Gereksinim: curl + jq.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/data/bots"
OUT="${OUT_DIR}/bot-ranges.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq gerekli (apt install jq / brew install jq). Alternatif: worker otomatik uretir."
  exit 1
fi

mkdir -p "${OUT_DIR}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# bot adi -> kaynak URL'ler (Google'in 3 kaynagi tek bota birlesir)
declare -A SOURCES=(
  ["Googlebot"]="https://developers.google.com/static/search/apis/ipranges/googlebot.json https://developers.google.com/static/search/apis/ipranges/special-crawlers.json https://developers.google.com/static/search/apis/ipranges/user-triggered-fetchers.json"
  ["Bingbot"]="https://www.bing.com/toolbox/bingbot.json"
)

extract() { jq -r '.prefixes[]? | (.ipv4Prefix // .ipv6Prefix) // empty'; }

bots_json="{}"
for bot in "${!SOURCES[@]}"; do
  : > "${tmp}/${bot}.txt"
  for url in ${SOURCES[$bot]}; do
    echo "Indiriliyor: ${bot} <- ${url}"
    curl -fsSL "${url}" | extract >> "${tmp}/${bot}.txt" || echo "  uyari: ${url} alinamadi"
  done
  arr="$(sort -u "${tmp}/${bot}.txt" | jq -R . | jq -s .)"
  bots_json="$(jq --arg b "${bot}" --argjson a "${arr}" '. + {($b): $a}' <<<"${bots_json}")"
done

jq -n --argjson bots "${bots_json}" \
  '{generated: (now | todate), sources: ($bots | map_values("ok")), bots: $bots}' > "${OUT}"

echo "Yazildi: ${OUT}"
jq '{generated, counts: (.bots | map_values(length))}' "${OUT}"
echo "Engine'i yenileyin: docker compose restart engine  (veya worker bir sonraki turda yeniler)"
