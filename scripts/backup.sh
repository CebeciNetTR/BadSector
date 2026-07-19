#!/bin/bash
# BadSector backup — Postgres config + TLS certs + secrets.env (+ challenge HTML)
# Kullanim:
#   ./scripts/backup.sh
#   ./scripts/backup.sh --no-secrets          # secrets.env olmadan
#   OUT=./backups ./scripts/backup.sh
#
# Cikti: badsector-backup-YYYYMMDD-HHMMSS.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

INCLUDE_SECRETS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-secrets) INCLUDE_SECRETS=0; shift ;;
    -h|--help)
      echo "Usage: $0 [--no-secrets]"
      exit 0
      ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

OUT_DIR="${OUT:-$ROOT/backups}"
mkdir -p "$OUT_DIR"
STAMP=$(date -u +%Y%m%d-%H%M%S)
ZIP="$OUT_DIR/badsector-backup-$STAMP.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> API uzerinden backup (JWT gerekmez — localhost script docker exec)"
# Host script: API container icinde curl yoksa dogrudan go yolu yok.
# En guvenilir: docker compose exec api wget backup endpoint — auth lazim.
# Bu yuzden: pg yok, API'ye token ile veya backup paketini compose run.
# Pratik yol: API health + authenticated curl from host if UI token;
# veya backup binary. Simdilik API'ye admin JWT olmadan da calissin diye
# container icinden env ile backup ureten kucuk yardimci kullanmiyoruz —
# host'tan docker compose cp + pg_dump alternatifi:

# Tercih: API endpoint (operator once login token alir) — script token ister.
# Alternatif: docker compose exec api ile health check sonra
# python/go yok — zip'i API'den cekmek icin TOKEN.

TOKEN="${BADSECTOR_BACKUP_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  echo "BADSECTOR_BACKUP_TOKEN yok — API login ile al:"
  echo "  TOKEN=\$(curl -sS -X POST http://127.0.0.1:8080/api/v1/auth/login \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"username\":\"USER\",\"password\":\"PASS\"}' | jq -r .token)"
  echo "  BADSECTOR_BACKUP_TOKEN=\$TOKEN $0"
  echo ""
  echo "Veya panelden Backup sayfasini kullan."
  exit 1
fi

QS="include_secrets=true"
[[ "$INCLUDE_SECRETS" == "0" ]] && QS="include_secrets=false"

curl -sS -f -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:8080/api/v1/backup?$QS" \
  -o "$ZIP"

echo "OK: $ZIP"
ls -lh "$ZIP"
echo ""
echo "Secrets politikasi: zip icinde secrets.env var ( --no-secrets degilse )."
echo "Zip'i guvenli sakla; public git'e koyma."
