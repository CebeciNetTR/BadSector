#!/bin/sh
# BadSector HAProxy entrypoint
#
# HAProxy'nin Lua runtime'i (http-req action) icinde DNS/hostname cozumlemesi
# guvenilir degildir (HAProxy Lua API "runtime modda DNS solve yapilamaz" der).
# Bu yuzden BADSECTOR_REDIS_HOST bir hostname ise (docker-compose service adi
# gibi, orn. "redis"), burada -- container henuz baslamadan, bloklamanin hic
# sorun olmadigi bir noktada -- bir kerelik cozumleyip sabit IP olarak env'e
# yaziyoruz. ban_check.lua boylece hep hazir bir IP gorur, kendi DNS cozmeye
# calismaz.
set -e

is_ip() {
    case "$1" in
        *[a-zA-Z]*) return 1 ;;
        *) return 0 ;;
    esac
}

# Hostname -> IPv4 cozumleme. Alpine/busybox surumleri arasinda nslookup ciktisi
# degistigi icin birden fazla yontemi sirayla dener; ilk gecerli IPv4'u dondurur.
resolve_ipv4() {
    _host="$1"
    _ip=""

    # 1) getent (varsa en guveniliri)
    if command -v getent >/dev/null 2>&1; then
        _ip=$(getent ahostsv4 "$_host" 2>/dev/null | awk '{print $1; exit}')
        [ -z "$_ip" ] && _ip=$(getent hosts "$_host" 2>/dev/null | awk '{print $1; exit}')
    fi

    # 2) ping (busybox'ta hep var, cikti formati stabil: "PING host (IP): ...")
    if [ -z "$_ip" ] && command -v ping >/dev/null 2>&1; then
        _ip=$(ping -c 1 -w 1 "$_host" 2>/dev/null \
            | sed -n 's/.*(\([0-9][0-9.]*\)).*/\1/p' | head -n 1)
    fi

    # 3) nslookup — cevap blogundaki ("Name:" sonrasi) ilk IPv4. Alanlari tarar,
    #    boylece "Address: IP", "Address 1: IP" ve "Address 1: IP hostname" ile
    #    sondaki ":53" bicimlerinin hepsini tolere eder.
    if [ -z "$_ip" ] && command -v nslookup >/dev/null 2>&1; then
        _ip=$(nslookup "$_host" 2>/dev/null | awk '
            /^Name:/ { ans=1; next }
            ans && /Address/ {
                for (i = 1; i <= NF; i++) {
                    f = $i; sub(/:.*/, "", f);
                    if (f ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print f; exit }
                }
            }')
    fi

    case "$_ip" in
        [0-9]*.[0-9]*.[0-9]*.[0-9]*) echo "$_ip" ;;
        *) echo "" ;;
    esac
}

# --- site-ratelimit map dosyasini tohumla ---
# maps/ dizini bir docker volume ile golgelenmis ve bos olabilir. HAProxy config
# bu dosyayi ("map_str_int(.../site-ratelimit.map)") baslangicta yukler; dosya yoksa
# HAProxy hic ayaga kalkmaz. O yuzden eksikse varsayilan sablondan kopyaliyoruz.
MAP_DIR="/usr/local/etc/haproxy/maps"
MAP_FILE="${MAP_DIR}/site-ratelimit.map"
DEFAULT_MAP="/usr/local/share/badsector/maps-default/site-ratelimit.map"
if [ ! -f "$MAP_FILE" ]; then
    mkdir -p "$MAP_DIR" 2>/dev/null || true
    if [ -f "$DEFAULT_MAP" ]; then
        cp "$DEFAULT_MAP" "$MAP_FILE" 2>/dev/null || true
    else
        : > "$MAP_FILE" 2>/dev/null || true
    fi
    if [ -f "$MAP_FILE" ]; then
        echo "badsector entrypoint: seeded $MAP_FILE" >&2
    else
        echo "badsector entrypoint: WARNING could not seed $MAP_FILE (check data/haproxy perms)" >&2
    fi
fi

if [ -n "$BADSECTOR_REDIS_HOST" ] && ! is_ip "$BADSECTOR_REDIS_HOST"; then
    resolved=$(resolve_ipv4 "$BADSECTOR_REDIS_HOST")
    # Yedek yol: /etc/hosts
    if [ -z "$resolved" ] && [ -f /etc/hosts ]; then
        resolved=$(awk -v h="$BADSECTOR_REDIS_HOST" '$2==h{print $1; exit}' /etc/hosts)
    fi

    if [ -n "$resolved" ]; then
        echo "badsector entrypoint: resolved $BADSECTOR_REDIS_HOST -> $resolved" >&2
        export BADSECTOR_REDIS_HOST="$resolved"
    else
        echo "badsector entrypoint: WARNING could not resolve $BADSECTOR_REDIS_HOST, leaving as-is (attack-mode edge checks will be skipped)" >&2
    fi
fi

# Client IP: BADSECTOR_CLOUDFLARE=true|false → maps/client-ip-policy.cfg (volume yazilabilir)
apply_client_ip_policy() {
    mkdir -p "$MAP_DIR" 2>/dev/null || true
    _policy="${MAP_DIR}/client-ip-policy.cfg"
    _cf=$(echo "${BADSECTOR_CLOUDFLARE:-false}" | tr '[:upper:]' '[:lower:]')
    case "$_cf" in
        1|true|yes|on) _mode=cloudflare ;;
        *) _mode=edge ;;
    esac

    if [ "$_mode" = "cloudflare" ]; then
        cat > "$_policy" <<'EOF' || return 1
# BADSECTOR_CLOUDFLARE=true — CF-Connecting-IP guvenilir; X-Real-IP ondan.
    http-request del-header True-Client-IP
    http-request del-header X-Client-IP
    http-request del-header X-Forwarded-For
    http-request set-header X-Real-IP %[req.hdr(CF-Connecting-IP)] if { req.hdr(CF-Connecting-IP) -m found }
    http-request set-header X-Real-IP %[src] unless { req.hdr(CF-Connecting-IP) -m found }
    option forwardfor
EOF
        echo "badsector entrypoint: client IP policy = cloudflare" >&2
    else
        cat > "$_policy" <<'EOF' || return 1
# BADSECTOR_CLOUDFLARE=false — edge; spoof header sil, X-Real-IP=%[src]
    http-request del-header CF-Connecting-IP
    http-request del-header True-Client-IP
    http-request del-header X-Client-IP
    http-request del-header X-Forwarded-For
    http-request set-header X-Real-IP %[src]
    option forwardfor
EOF
        echo "badsector entrypoint: client IP policy = edge" >&2
    fi
}

if ! apply_client_ip_policy; then
    echo "badsector entrypoint: WARNING could not write client-ip-policy.cfg" >&2
    # Son care: image default
    if [ ! -f "${MAP_DIR}/client-ip-policy.cfg" ] && [ -f /usr/local/share/badsector/maps-default/client-ip-policy.cfg ]; then
        cp /usr/local/share/badsector/maps-default/client-ip-policy.cfg "${MAP_DIR}/client-ip-policy.cfg" 2>/dev/null || true
    fi
fi

exec "$@"
