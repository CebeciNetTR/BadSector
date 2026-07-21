#!/bin/bash
# BadSector attack-mode kernel blocks (iptables + ipset).
# TLS / HAProxy / Lua'dan ONCE — INPUT zincirinde DROP.
#
# Ulke: acik block listesi (CN, BR, …) → ipdeny CIDR → ipset bs_attack_geo
# allow_only KULLANILMAZ — yalnizca listelenen ulkeler duser.
# ASN:  bs:ip_hits → MMDB → bs_banned ipset

ATTACK_GEO_IPSET="${ATTACK_GEO_IPSET:-bs_attack_geo}"
ATTACK_GEO_ZONES_DIR="${ATTACK_GEO_ZONES_DIR:-/var/lib/badsector/country-zones}"
ASN_MMDB="${BADSECTOR_ASN_MMDB:-/etc/badsector/geoip/GeoLite2-ASN.mmdb}"
ATTACK_KERNEL_COUNTRIES="${ATTACK_KERNEL_COUNTRIES:-}"
ATTACK_KERNEL_ASNS="${ATTACK_KERNEL_ASNS:-}"
ATTACK_KERNEL_EXEMPT_COUNTRIES="${ATTACK_KERNEL_EXEMPT_COUNTRIES:-TR}"
ATTACK_ASN_HIT_MIN="${ATTACK_ASN_HIT_MIN:-1}"
ATTACK_ASN_SCAN_LIMIT="${ATTACK_ASN_SCAN_LIMIT:-8000}"

_last_geo_sig=""
_geo_iptables_on=false

is_attack_mode() {
    local v
    v=$($REDIS GET bs:attack_mode 2>/dev/null | tr -d '\r')
    [[ "$v" == "1" ]]
}

redis_get_or_empty() {
    local key="$1"
    local v
    v=$($REDIS GET "$key" 2>/dev/null | tr -d '\r')
    [[ "$v" == "(nil)" || "$v" == "null" ]] && v=""
    echo "$v"
}

get_kernel_countries() {
    local from_redis
    from_redis=$(redis_get_or_empty "bs:attack_kernel_countries")
    if [[ -n "$from_redis" ]]; then
        echo "$from_redis"
        return
    fi
    echo "$ATTACK_KERNEL_COUNTRIES"
}

get_kernel_asns() {
    local from_redis
    from_redis=$(redis_get_or_empty "bs:attack_kernel_asns")
    if [[ -n "$from_redis" ]]; then
        echo "$from_redis"
        return
    fi
    echo "$ATTACK_KERNEL_ASNS"
}

get_kernel_exempt_countries() {
    local from_redis exempt
    from_redis=$(redis_get_or_empty "bs:attack_kernel_exempt_countries")
    exempt="${from_redis:-$ATTACK_KERNEL_EXEMPT_COUNTRIES}"
    echo "$exempt" | tr '[:lower:]' '[:upper:]'
}

country_is_exempt() {
    local cc="$1" exempt_csv part
    cc=$(echo "$cc" | tr '[:lower:]' '[:upper:]')
    exempt_csv=$(get_kernel_exempt_countries)
    IFS=',' read -ra _exempt <<< "$exempt_csv"
    for part in "${_exempt[@]}"; do
        part=$(echo "$part" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
        [[ "$part" == "$cc" ]] && return 0
    done
    return 1
}

ensure_attack_geo_ipset() {
    if ! ipset list "$ATTACK_GEO_IPSET" &>/dev/null; then
        ipset create "$ATTACK_GEO_IPSET" hash:net family inet hashsize 65536 maxelem 1048576
        log "ipset '$ATTACK_GEO_IPSET' olusturuldu (attack geo CIDR)"
    fi
}

ensure_attack_geo_iptables() {
    if $_geo_iptables_on; then
        return
    fi
    if ! iptables -C INPUT -m set --match-set "$ATTACK_GEO_IPSET" src -j DROP 2>/dev/null; then
        iptables -I INPUT 2 -m set --match-set "$ATTACK_GEO_IPSET" src -j DROP
        log "iptables ATTACK-GEO: INPUT -m set --match-set $ATTACK_GEO_IPSET src -j DROP"
    fi
    _geo_iptables_on=true
}

remove_attack_geo_iptables() {
    while iptables -C INPUT -m set --match-set "$ATTACK_GEO_IPSET" src -j DROP 2>/dev/null; do
        iptables -D INPUT -m set --match-set "$ATTACK_GEO_IPSET" src -j DROP
    done
    _geo_iptables_on=false
}

teardown_attack_kernel_geo() {
    remove_attack_geo_iptables
    ipset flush "$ATTACK_GEO_IPSET" 2>/dev/null || true
    _last_geo_sig=""
}

load_country_zone_into_ipset() {
    local cc="$1" zone url
    cc=$(echo "$cc" | tr '[:upper:]' '[:lower:]')
    [[ -z "$cc" ]] && return 0
    if country_is_exempt "$cc"; then
        log "ATTACK-GEO skip exempt country: ${cc^^}"
        return 0
    fi
    zone="$ATTACK_GEO_ZONES_DIR/${cc}.zone"
    if [[ ! -s "$zone" ]]; then
        mkdir -p "$ATTACK_GEO_ZONES_DIR"
        url="https://www.ipdeny.com/ipblocks/data/countries/${cc}.zone"
        if ! curl -sfL --connect-timeout 10 --max-time 60 "$url" -o "$zone.tmp"; then
            rm -f "$zone.tmp"
            log "WARN: ulke zone indirilemedi: $cc ($url)"
            return 1
        fi
        mv "$zone.tmp" "$zone"
    fi
    local cidr added=0
    while IFS= read -r cidr; do
        [[ -z "$cidr" || "$cidr" =~ ^# ]] && continue
        if ipset -exist add "$ATTACK_GEO_IPSET" "$cidr" 2>/dev/null; then
            added=$((added + 1))
        fi
    done < "$zone"
    log "ATTACK-GEO zone ${cc^^}: +$added CIDR"
}

build_block_country_geo_ipset() {
    local countries_csv="$1" cc part
    IFS=',' read -ra _cc <<< "$countries_csv"
    for part in "${_cc[@]}"; do
        cc=$(echo "$part" | tr -d ' ')
        [[ -z "$cc" ]] && continue
        load_country_zone_into_ipset "$cc" || true
    done
}

sync_attack_kernel_geo() {
    if ! is_attack_mode; then
        if [[ -n "$_last_geo_sig" ]] || $_geo_iptables_on; then
            teardown_attack_kernel_geo
            log "ATTACK-KERNEL-GEO: attack kapali — kurallar kaldirildi"
        fi
        return
    fi

    local countries exempt_csv sig
    countries=$(get_kernel_countries)
    exempt_csv=$(get_kernel_exempt_countries)
    [[ -z "$countries" ]] && return

    sig="block|${countries}|${exempt_csv}"
    if [[ "$sig" == "$_last_geo_sig" ]]; then
        ensure_attack_geo_ipset
        ensure_attack_geo_iptables
        return
    fi

    ensure_attack_geo_ipset
    ipset flush "$ATTACK_GEO_IPSET"
    log "ATTACK-KERNEL-GEO: block list yukleniyor: $countries (exempt=$exempt_csv)"
    build_block_country_geo_ipset "$countries"

    ensure_attack_geo_iptables
    _last_geo_sig="$sig"
    local cnt
    cnt=$(ipset list "$ATTACK_GEO_IPSET" 2>/dev/null | awk '/Number of entries/ {print $4}')
    log "ATTACK-KERNEL-GEO: hazir — $cnt CIDR kernel DROP (HAProxy oncesi)"
}

lookup_asn() {
    local ip="$1" asn
    if [[ ! -f "$ASN_MMDB" ]]; then
        return 1
    fi
    if [[ ! -x /usr/local/openresty/bin/resty ]]; then
        return 1
    fi
    asn=$(BADSECTOR_ASN_MMDB="$ASN_MMDB" /usr/local/openresty/bin/resty /usr/local/bin/asn-lookup-one.lua "$ip" 2>/dev/null | tr -d '\r')
    [[ -n "$asn" ]] && echo "$asn"
}

asn_in_kernel_list() {
    local asn="$1" list_csv part
    list_csv=$(get_kernel_asns)
    [[ -z "$list_csv" || -z "$asn" ]] && return 1
    IFS=',' read -ra _asns <<< "$list_csv"
    for part in "${_asns[@]}"; do
        part=$(echo "$part" | tr -d ' ')
        [[ "$part" == "$asn" ]] && return 0
    done
    return 1
}

sync_attack_kernel_asn() {
    if ! is_attack_mode; then
        return
    fi
    local asns
    asns=$(get_kernel_asns)
    [[ -z "$asns" ]] && return
    if [[ ! -f "$ASN_MMDB" ]]; then
        return
    fi
    if [[ ! -x /usr/local/openresty/bin/resty ]]; then
        return
    fi

    local ips ip asn banned=0
    ips=$($REDIS ZRANGEBYSCORE bs:ip_hits "$ATTACK_ASN_HIT_MIN" +inf 2>/dev/null | head -n "$ATTACK_ASN_SCAN_LIMIT" | tr -d '\r')
    [[ -z "$ips" ]] && return

    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        is_trusted "$ip" && continue
        if ipset test "$IPSET_NAME" "$ip" 2>/dev/null; then
            continue
        fi
        asn=$(lookup_asn "$ip")
        [[ -z "$asn" ]] && continue
        if asn_in_kernel_list "$asn"; then
            ban_ip "$ip"
            banned=$((banned + 1))
        fi
    done <<< "$ips"

    if [[ "$banned" -gt 0 ]]; then
        log "ATTACK-KERNEL-ASN: $banned IP kernel ban (ASN list: $asns)"
    fi
}

sync_attack_kernel() {
    sync_attack_kernel_geo
    sync_attack_kernel_asn
}
