#!/bin/bash
# BadSector IP Watcher
# Redis'teki bs:ip_hits sorted set'ini izler.
# Esigi asan IP'leri iptables (ipset) + Redis ile banlar.
# Gece 00:00'da hit sayaclarini ve ipset'i temizler.
#
# NOT: Bilincli olarak "set -e" KULLANMIYORUZ. Bu uzun-omurlu bir daemon;
# Redis bir an erisilemez oldugunda (flood/restart) tek bir komut hatasi tum
# script'i oldurup crash-loop'a sokmamali. Hatalar tolere edilir, dongu devam eder.

REDIS_HOST="${BADSECTOR_REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${BADSECTOR_REDIS_PORT:-6379}"
BAN_THRESHOLD="${BAN_THRESHOLD:-1000}"      # Bu kadar hit = ban
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"      # Saniyede bir kontrol
BAN_TTL="${BAN_TTL:-86400}"                 # Ban suresi (saniye) - varsayilan 24 saat
IPSET_NAME="bs_banned"
# Virgul ile: asla banlanmaz + iptables ACCEPT. Bos = kimse muaf degil.
TRUSTED_IPS="${BADSECTOR_TRUSTED_IPS:-}"

REDIS="redis-cli -h $REDIS_HOST -p $REDIS_PORT"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1"
}

is_trusted() {
    local ip="$1"
    local part
    IFS=',' read -ra _parts <<< "$TRUSTED_IPS"
    for part in "${_parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [[ "$part" == "$ip" ]] && return 0
    done
    return 1
}

ensure_trusted_accept() {
    local part
    IFS=',' read -ra _parts <<< "$TRUSTED_IPS"
    for part in "${_parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [[ -z "$part" ]] && continue
        # ACCEPT en uste — ipset DROP'tan once
        if ! iptables -C INPUT -s "$part" -j ACCEPT 2>/dev/null; then
            iptables -I INPUT 1 -s "$part" -j ACCEPT
            log "iptables ACCEPT (trusted): $part"
        fi
        ipset del "$IPSET_NAME" "$part" 2>/dev/null || true
        $REDIS DEL "bs:ban:$part" > /dev/null 2>&1 || true
    done
}

setup_ipset() {
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        # maxelem varsayilani 65536'dir; buyuk flood'da ban sayisi bunu asinca
        # "ipset add" sessizce basarisiz olur. 1M'e cikariyoruz.
        ipset create "$IPSET_NAME" hash:ip timeout "$BAN_TTL" maxelem 1048576
        log "ipset '$IPSET_NAME' olusturuldu (timeout: ${BAN_TTL}s)"
    fi

    # iptables kurali yoksa ekle
    if ! iptables -C INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
        iptables -I INPUT -m set --match-set "$IPSET_NAME" src -j DROP
        log "iptables kurali eklendi: INPUT -m set --match-set $IPSET_NAME src -j DROP"
    fi

    ensure_trusted_accept
}

ban_ip() {
    local ip="$1"
    if is_trusted "$ip"; then
        log "SKIP ban (trusted): $ip"
        return
    fi
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

    ensure_trusted_accept

    log "=== Gunluk temizlik tamamlandi ==="
}

# Bir onceki temizlik tarihini takip et
last_reset_day=""

log "BadSector IP Watcher baslatildi"
log "Esik: $BAN_THRESHOLD hit | Kontrol suresi: ${CHECK_INTERVAL}s | Ban TTL: ${BAN_TTL}s"
log "Trusted IPs: $TRUSTED_IPS"

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
