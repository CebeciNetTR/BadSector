#!/bin/bash
# BadSector IP Watcher
# Redis'teki bs:ip_hits sorted set'ini izler.
# Esigi asan IP'leri iptables (ipset) + Redis ile banlar.
# Gece 00:00'da hit sayaclarini ve gecici ipset'i temizler (kalici ban korunur).
# Stale prune: 10dk+ gormeyen VE hit < HIT_MIN_KEEP → listeden dusur.
#
# NOT: Bilincli olarak "set -e" KULLANMIYORUZ. Bu uzun-omurlu bir daemon;
# Redis bir an erisilemez oldugunda (flood/restart) tek bir komut hatasi tum
# script'i oldurup crash-loop'a sokmamali. Hatalar tolere edilir, dongu devam eder.

REDIS_HOST="${BADSECTOR_REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${BADSECTOR_REDIS_PORT:-6379}"
BAN_THRESHOLD="${BAN_THRESHOLD:-1000}"      # Bu kadar hit = ban
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"      # Saniyede bir kontrol
BAN_TTL="${BAN_TTL:-86400}"                 # Ban suresi (saniye) - varsayilan 24 saat
# Tekrarlayan saldirgan: 24s icinde BAN_STRIKES_DAY veya 7 gun icinde BAN_STRIKES_WEEK ban → kalici
BAN_STRIKES_DAY="${BAN_STRIKES_DAY:-3}"
BAN_STRIKES_WEEK="${BAN_STRIKES_WEEK:-7}"
# bs:ban:* → ipset tam taramasi (15k+ ban'da pahali). added=0 ise seyrek tekrarla.
KERNEL_SYNC_INTERVAL="${KERNEL_SYNC_INTERVAL:-120}"
KERNEL_SYNC_INTERVAL_IDLE="${KERNEL_SYNC_INTERVAL_IDLE:-900}"
PRUNE_INTERVAL="${PRUNE_INTERVAL:-60}"
HIT_STALE_SEC="${HIT_STALE_SEC:-600}"       # Son gorulme bundan eskiyse "stale"
HIT_MIN_KEEP="${HIT_MIN_KEEP:-10}"          # Stale + hit < bu → prune
IPSET_NAME="bs_banned"
PERM_IPSET="${PERM_IPSET:-bs_banned_perm}"
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
        ipset del "$PERM_IPSET" "$part" 2>/dev/null || true
        $REDIS DEL "bs:ban:$part" > /dev/null 2>&1 || true
        $REDIS DEL "bs:ban_strikes:day:$part" > /dev/null 2>&1 || true
        $REDIS DEL "bs:ban_strikes:week:$part" > /dev/null 2>&1 || true
    done
}

setup_perm_ipset() {
    if ! ipset list "$PERM_IPSET" &>/dev/null; then
        ipset create "$PERM_IPSET" hash:ip maxelem 1048576
        log "ipset '$PERM_IPSET' olusturuldu (kalici ban, timeout yok)"
    fi
    if ! iptables -C INPUT -m set --match-set "$PERM_IPSET" src -j DROP 2>/dev/null; then
        iptables -I INPUT -m set --match-set "$PERM_IPSET" src -j DROP
        log "iptables kurali eklendi: INPUT -m set --match-set $PERM_IPSET src -j DROP"
    fi
}

# Her ban olayinda strike say; esik asilirsa permanent=1 doner.
# stdout: day week permanent
record_ban_strike() {
    local ip="$1"
    $REDIS --raw EVAL "
local ip = ARGV[1]
local day_lim = tonumber(ARGV[2])
local week_lim = tonumber(ARGV[3])
local dk = 'bs:ban_strikes:day:' .. ip
local wk = 'bs:ban_strikes:week:' .. ip
local day = redis.call('INCR', dk)
if day == 1 then redis.call('EXPIRE', dk, 86400) end
local week = redis.call('INCR', wk)
if week == 1 then redis.call('EXPIRE', wk, 604800) end
local perm = 0
if day >= day_lim or week >= week_lim then perm = 1 end
return {day, week, perm}
" 0 "$ip" "$BAN_STRIKES_DAY" "$BAN_STRIKES_WEEK" 2>/dev/null | tr -d '\r'
}

is_permanent_ban_key() {
    local key="$1"
    local ttl val
    ttl=$($REDIS TTL "$key" 2>/dev/null | tr -d '\r')
    [[ "$ttl" == "-1" ]] && return 0
    val=$($REDIS GET "$key" 2>/dev/null | tr -d '\r')
    [[ "$val" == permanent:* ]] && return 0
    return 1
}

add_perm_ban_kernel() {
    local ip="$1"
    ipset -exist add "$PERM_IPSET" "$ip" 2>/dev/null || true
    ipset del "$IPSET_NAME" "$ip" 2>/dev/null || true
}

add_temp_ban_kernel() {
    local ip="$1"
    local ttl="${2:-$BAN_TTL}"
    ipset -exist add "$IPSET_NAME" "$ip" timeout "$ttl" 2>/dev/null
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
    setup_perm_ipset
}

ban_ip() {
    local ip="$1"
    local reason="${2:-watcher}"
    if is_trusted "$ip"; then
        log "SKIP ban (trusted): $ip"
        return
    fi

    local strike_out day week permanent
    strike_out=$(record_ban_strike "$ip")
    day=$(echo "$strike_out" | awk 'NR==1{print $1}')
    week=$(echo "$strike_out" | awk 'NR==2{print $1}')
    permanent=$(echo "$strike_out" | awk 'NR==3{print $1}')
    [[ -z "$day" || ! "$day" =~ ^[0-9]+$ ]] && day=0
    [[ -z "$week" || ! "$week" =~ ^[0-9]+$ ]] && week=0
    [[ -z "$permanent" ]] && permanent=0

    if [[ "$permanent" == "1" ]]; then
        add_perm_ban_kernel "$ip"
        $REDIS SET "bs:ban:$ip" "permanent:$reason" > /dev/null
        log "PERMA-BANNED: $ip | strikes day=$day week=$week | $PERM_IPSET + Redis (TTL yok)"
        return
    fi

    if add_temp_ban_kernel "$ip" "$BAN_TTL"; then
        $REDIS SETEX "bs:ban:$ip" "$BAN_TTL" "$reason" > /dev/null
        log "BANNED: $ip | strikes day=$day week=$week | TTL: ${BAN_TTL}s"
    else
        log "WARN: ipset add failed: $ip"
    fi
}

# Engine/JS/GeoIP ban'lari sadece Redis'e yazar → HAProxy TLS sonrasi silent-drop.
# Kernel'de yoksa CPU yine yanar. Redis bs:ban:* → ipset senkronu (TTL korunur).
_last_kernel_sync_at=0
_last_kernel_sync_added=1
_last_prune_at=0
sync_redis_bans_to_kernel() {
    local now=$(( $(date +%s) ))
    local interval="$KERNEL_SYNC_INTERVAL"
    if [[ "$_last_kernel_sync_added" -eq 0 ]]; then
        interval="$KERNEL_SYNC_INTERVAL_IDLE"
    fi
    if (( now - _last_kernel_sync_at < interval )); then
        return
    fi
    _last_kernel_sync_at=$now

    local t0=$now added=0 ip ttl keys key cursor="0"
    while true; do
        # redis-cli SCAN: cursor + optional keys
        local out
        out=$($REDIS --raw SCAN "$cursor" MATCH "bs:ban:*" COUNT 200 2>/dev/null | tr -d '\r')
        [[ -z "$out" ]] && break
        cursor=$(echo "$out" | head -n1)
        keys=$(echo "$out" | tail -n +2)
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            ip="${key#bs:ban:}"
            is_trusted "$ip" && continue
            if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$ip" =~ : ]]; then
                continue
            fi
            if is_permanent_ban_key "$key"; then
                if ! ipset test "$PERM_IPSET" "$ip" 2>/dev/null; then
                    if ipset add "$PERM_IPSET" "$ip" 2>/dev/null; then
                        added=$((added + 1))
                        ipset del "$IPSET_NAME" "$ip" 2>/dev/null || true
                    fi
                fi
                continue
            fi
            ttl=$($REDIS TTL "$key" 2>/dev/null | tr -d '\r')
            [[ -z "$ttl" || "$ttl" -lt 1 ]] && ttl="$BAN_TTL"
            if ipset test "$IPSET_NAME" "$ip" 2>/dev/null; then
                continue
            fi
            if ipset test "$PERM_IPSET" "$ip" 2>/dev/null; then
                continue
            fi
            if ipset add "$IPSET_NAME" "$ip" timeout "$ttl" 2>/dev/null; then
                added=$((added + 1))
            fi
        done <<< "$keys"
        [[ "$cursor" == "0" ]] && break
    done
    _last_kernel_sync_added=$added
    local elapsed=$(( $(date +%s) - t0 ))
    if [[ "$added" -gt 0 ]]; then
        log "KERNEL-SYNC: $added Redis ban → ipset (${elapsed}s, next in ${KERNEL_SYNC_INTERVAL}s)"
    elif (( elapsed > 30 )); then
        log "KERNEL-SYNC: 0 yeni (${elapsed}s, ${interval}s aralik — buyuk ban listesi normal)"
    fi
}

# Dusuk hit + uzun suredir gorulmeyen IP'leri bs:ip_hits / bs:ip_seen'den sil.
prune_stale_hits() {
    local now cutoff removed
    now=$(date +%s)
    if (( now - _last_prune_at < PRUNE_INTERVAL )); then
        return
    fi
    _last_prune_at=$now
    cutoff=$((now - HIT_STALE_SEC))
    removed=$($REDIS EVAL "
local cutoff = tonumber(ARGV[1])
local min_keep = tonumber(ARGV[2])
local removed = 0
local low = redis.call('ZRANGEBYSCORE', 'bs:ip_hits', '-inf', min_keep - 1)
for _, ip in ipairs(low) do
  local seen = redis.call('ZSCORE', 'bs:ip_seen', ip)
  if (not seen) or (tonumber(seen) <= cutoff) then
    redis.call('ZREM', 'bs:ip_hits', ip)
    redis.call('ZREM', 'bs:ip_seen', ip)
    removed = removed + 1
  end
end
return removed
" 0 "$cutoff" "$HIT_MIN_KEEP" 2>/dev/null | tr -d '\r')
    if [[ -n "$removed" && "$removed" =~ ^[0-9]+$ && "$removed" -gt 0 ]]; then
        log "PRUNE: removed $removed stale low-hit IPs (stale>${HIT_STALE_SEC}s hit<${HIT_MIN_KEEP})"
    fi
}

daily_reset() {
    log "=== Gunluk temizlik basliyor ==="

    # Hit sayaclarini sifirla
    $REDIS DEL bs:ip_hits bs:ip_seen > /dev/null
    log "Redis bs:ip_hits + bs:ip_seen sifirlandi"

    # Gecici ban ipset'i temizle — kalici ban (bs_banned_perm) dokunulmaz
    ipset flush "$IPSET_NAME" 2>/dev/null && log "ipset '$IPSET_NAME' temizlendi (kalici '$PERM_IPSET' korundu)"

    ensure_trusted_accept

    log "=== Gunluk temizlik tamamlandi ==="
}

# Bir onceki temizlik tarihini takip et
last_reset_day=""

log "BadSector IP Watcher baslatildi"
log "Esik: $BAN_THRESHOLD hit | Kontrol: ${CHECK_INTERVAL}s | Ban TTL: ${BAN_TTL}s"
log "Kalici ban: >=${BAN_STRIKES_DAY}/24s veya >=${BAN_STRIKES_WEEK}/7d strike → $PERM_IPSET"
log "Kernel sync: ${KERNEL_SYNC_INTERVAL}s (idle ${KERNEL_SYNC_INTERVAL_IDLE}s) | Prune: ${PRUNE_INTERVAL}s"
log "Prune stale: >${HIT_STALE_SEC}s AND hit<${HIT_MIN_KEEP}"
log "Trusted IPs: $TRUSTED_IPS"

# Kernel attack blocks (iptables/ipset — HAProxy oncesi)
# shellcheck source=attack-kernel.sh
source /usr/local/bin/attack-kernel.sh

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

    prune_stale_hits
    sync_redis_bans_to_kernel
    sync_attack_kernel

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
            $REDIS ZREM bs:ip_seen "$ip" > /dev/null
        fi
    done <<< "$HIGH_HIT_IPS"
done
