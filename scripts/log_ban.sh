#!/bin/bash
# BadSector Host Log Ban Script
# Run this on the host VPS.
# It reads HAProxy logs, extracts IPs causing TCP rejects/bad requests, and bans them via ipset.

IPSET_NAME="bs_banned"
BAN_TTL=86400  # 24 hours
TRUSTED_IPS="${BADSECTOR_TRUSTED_IPS:-}"

is_trusted() {
    local ip="$1" part
    IFS=',' read -ra _parts <<< "$TRUSTED_IPS"
    for part in "${_parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [[ "$part" == "$ip" ]] && return 0
    done
    return 1
}

# Ensure ipset exists
if ! ipset list "$IPSET_NAME" &>/dev/null; then
    ipset create "$IPSET_NAME" hash:ip timeout $BAN_TTL
    echo "Created ipset: $IPSET_NAME"
fi

# Ensure iptables rule exists
if ! iptables -C INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
    iptables -I INPUT -m set --match-set "$IPSET_NAME" src -j DROP
    echo "Added iptables rule for $IPSET_NAME"
fi

# Get the HAProxy container name dynamically
HAPROXY_CONTAINER=$(docker ps --filter name=haproxy --format "{{.Names}}" | head -n 1)

if [ -z "$HAPROXY_CONTAINER" ]; then
    echo "Error: HAProxy container not found!"
    exit 1
fi

echo "Scanning logs for container: $HAPROXY_CONTAINER..."

# Extract IPs with > 30 bad connections / policy rejects in the last 2000 lines
docker logs --tail 2000 "$HAPROXY_CONTAINER" 2>/dev/null | grep -E "PR--|<BADREQ>" | awk '{
    for(i=1; i<=NF; i++) {
        if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/) {
            split($i, a, ":")
            print a[1]
            break
        }
    }
}' | sort | uniq -c | while read count ip; do
    if [ "$count" -gt 30 ]; then
        if is_trusted "$ip"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SKIP trusted: $ip"
            continue
        fi
        if ipset add "$IPSET_NAME" "$ip" timeout $BAN_TTL 2>/dev/null; then
            # Sync with Redis for OpenResty consistency
            docker exec -d $(docker ps --filter name=redis --format "{{.Names}}" | head -n 1) redis-cli SETEX "bs:ban:$ip" "$BAN_TTL" "1"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Banned IP: $ip ($count bad connections/rejects)"
        fi
    fi
done
