#!/bin/bash
# BadSector IP Watcher
# Redis'teki bs:ip_hits sorted set'ini izler.
# Esigi asan IP'leri iptables (ipset) + Redis ile banlar.
# Gece 00:00'da hit sayaclarini ve ipset'i temizler.

set -e

REDIS_HOST="${BADSECTOR_REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${BADSECTOR_REDIS_PORT:-6379}"
BAN_THRESHOLD="${BAN_THRESHOLD:-1000}"      # Bu kadar hit = ban
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"      # Saniyede bir kontrol
BAN_TTL="${BAN_TTL:-86400}"                 # Ban suresi (saniye) - varsayilan 24 saat
IPSET_NAME="bs_banned"

REDIS="redis-cli -h $REDIS_HOST -p $REDIS_PORT"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1"
}

setup_ipset() {
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        ipset create "$IPSET_NAME" hash:ip timeout "$BAN_TTL"
        log "ipset '$IPSET_NAME' olusturuldu (timeout: ${BAN_TTL}s)"
    fi

    # iptables kurali yoksa ekle
    if ! iptables -C INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
        iptables -I INPUT -m set --match-set "$IPSET_NAME" src -j DROP
        log "iptables kurali eklendi: INPUT -m set --match-set $IPSET_NAME src -j DROP"
    fi
}

ban_ip() {
    local ip="$1"
    # iptables ipset'e ekle (zaten varsa hata verme)
    if ipset add "$IPSET_NAME" "$ip" timeout "$BAN_TTL" 2>/dev/null; then
        # Redis ban listesine de ekle (engine katmani icin)
        $REDIS SETEX "bs:ban:$ip" "$BAN_TTL" "1" > /dev/null
        log "BANNED: $ip | iptables + Redis | TTL: ${BAN_TTL}s"
    fi
}

daily_reset() {
    log "=== Gunluk temizlik basliyor ==="

    # Hit sayaclarini sifirla
    $REDIS DEL bs:ip_hits > /dev/null
    log "Redis bs:ip_hits sifirlandi"

    # ipset'i temizle (yeni olustur)
    ipset flush "$IPSET_NAME" 2>/dev/null && log "ipset '$IPSET_NAME' temizlendi"

    log "=== Gunluk temizlik tamamlandi ==="
}

# Bir onceki temizlik tarihini takip et
last_reset_day=""

log "BadSector IP Watcher baslatildi"
log "Esik: $BAN_THRESHOLD hit | Kontrol suresi: ${CHECK_INTERVAL}s | Ban TTL: ${BAN_TTL}s"

setup_ipset

while true; do
    sleep "$CHECK_INTERVAL"

    # Gunluk reset kontrolu (gece 00:00)
    current_day=$(date +%Y-%m-%d)
    current_hour=$(date +%H)
    if [[ "$current_hour" == "00" && "$current_day" != "$last_reset_day" ]]; then
        daily_reset
        last_reset_day="$current_day"
    fi

    # Esigi asan IP'leri al ve satır sonu (\r) karakterlerini temizle
    HIGH_HIT_IPS=$($REDIS ZRANGEBYSCORE bs:ip_hits "$BAN_THRESHOLD" +inf 2>/dev/null | tr -d '\r')

    if [[ -z "$HIGH_HIT_IPS" ]]; then
        continue
    fi

    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        # Gecerli IPv4/IPv6 kontrolu
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$ip" =~ : ]]; then
            ban_ip "$ip"
            $REDIS ZREM bs:ip_hits "$ip" > /dev/null
        fi
    done <<< "$HIGH_HIT_IPS"
done
