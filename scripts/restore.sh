#!/bin/bash
# BadSector restore — yeni kutuda veya DR
#
#   ./scripts/restore.sh /path/to/badsector-backup.zip
#   ./scripts/restore.sh backup.zip --rotate-secrets   # JWT/challenge/admin sifre yenile
#   ./scripts/restore.sh backup.zip --keep-secrets     # backup'taki secrets (varsayilan)
#   ./scripts/restore.sh backup.zip --skip-secrets     # sadece DB+certs
#
# Secrets dosyasi: data/restore/secrets.env
# Sonra:  cp data/restore/secrets.env degerlerini .env'e birlestir
#         docker compose up -d
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE=keep
ZIP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rotate-secrets) MODE=rotate; shift ;;
    --keep-secrets) MODE=keep; shift ;;
    --skip-secrets) MODE=skip; shift ;;
    -h|--help)
      echo "Usage: $0 <backup.zip> [--keep-secrets|--rotate-secrets|--skip-secrets]"
      exit 0
      ;;
    *)
      if [[ -z "$ZIP" ]]; then ZIP=$1; shift; else echo "Unknown: $1"; exit 1; fi
      ;;
  esac
done

if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "backup zip gerekli"
  exit 1
fi

TOKEN="${BADSECTOR_BACKUP_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  echo "BADSECTOR_BACKUP_TOKEN gerekli (login JWT). Ornek:"
  echo "  TOKEN=\$(curl -sS -X POST http://127.0.0.1:8080/api/v1/auth/login -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"...\"}' | jq -r .token)"
  echo "  BADSECTOR_BACKUP_TOKEN=\$TOKEN $0 $ZIP --$MODE-secrets"
  exit 1
fi

echo "==> Restore ($MODE) $ZIP"
RESP=$(curl -sS -f -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@${ZIP}" \
  "http://127.0.0.1:8080/api/v1/backup/restore?secrets_mode=$MODE")

echo "$RESP" | tee /tmp/badsector-restore.json
echo ""

if [[ -f data/restore/secrets.env ]]; then
  echo "==> Secrets yazildi: data/restore/secrets.env"
  echo "Host .env'e birlestir (ornek):"
  echo "  # Mevcut .env'i yedekle"
  echo "  cp .env .env.bak.\$(date +%s)"
  echo "  # secrets.env satirlarini .env uzerine yaz (elle veya):"
  echo "  while IFS= read -r line; do"
  echo "    [[ \$line =~ ^# ]] && continue"
  echo "    [[ -z \$line ]] && continue"
  echo "    key=\${line%%=*}"
  echo "    grep -q \"^\${key}=\" .env && sed -i \"s|^\${key}=.*|\${line}|\" .env || echo \"\$line\" >> .env"
  echo "  done < data/restore/secrets.env"
  echo "  docker compose up -d"
  echo "  docker compose restart haproxy engine api watcher"
fi

echo "OK — runtime regenerate API tarafindan tetiklendi. HAProxy PEM icin: docker compose restart haproxy"
