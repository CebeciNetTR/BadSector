#!/bin/sh
set -e

RUNTIME="${BADSECTOR_RUNTIME:-/etc/badsector/runtime}"
SITES="${RUNTIME}/sites.json"

echo "badsector-engine: waiting for ${SITES}..."
i=0
while [ ! -f "${SITES}" ]; do
  i=$((i + 1))
  if [ "$i" -gt 120 ]; then
    echo "badsector-engine: timeout waiting for sites.json"
    exit 1
  fi
  sleep 1
done

echo "badsector-engine: config ready, starting OpenResty"
exec "$@"
