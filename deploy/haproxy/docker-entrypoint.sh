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
    resolved=""
    # Alpine busybox'ta nslookup applet'i varsayilan olarak bulunur.
    if command -v nslookup >/dev/null 2>&1; then
        resolved=$(nslookup "$BADSECTOR_REDIS_HOST" 2>/dev/null \
            | awk '/^Name:/{f=1; next} f && /^Address/{print $3; exit}')
    fi
    # Yedek yol: /etc/hosts icinde docker tarafindan zaten eklenmis olabilir.
    if [ -z "$resolved" ] && [ -f /etc/hosts ]; then
        resolved=$(awk -v h="$BADSECTOR_REDIS_HOST" '$2==h{print $1; exit}' /etc/hosts)
    fi

    if [ -n "$resolved" ]; then
        echo "badsector entrypoint: resolved $BADSECTOR_REDIS_HOST -> $resolved" >&2
        export BADSECTOR_REDIS_HOST="$resolved"
    else
        echo "badsector entrypoint: WARNING could not resolve $BADSECTOR_REDIS_HOST, leaving as-is" >&2
    fi
fi

exec "$@"
