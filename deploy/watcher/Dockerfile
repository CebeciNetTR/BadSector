# resty + lua-resty-maxminddb: engine ile ayni MMDB okuyucu (ayri MaxMind indirme yok)
FROM openresty/openresty:1.25.3.1-alpine AS resty
RUN apk add --no-cache libmaxminddb perl \
    && ln -sf /usr/lib/libmaxminddb.so.0 /usr/lib/libmaxminddb.so \
    && /usr/local/openresty/bin/opm get anjia0532/lua-resty-maxminddb

FROM alpine:3.19
RUN apk add --no-cache bash redis ipset iptables tzdata curl libmaxminddb \
    && ln -sf /usr/lib/libmaxminddb.so.0 /usr/lib/libmaxminddb.so

COPY --from=resty /usr/local/openresty/bin/resty /usr/local/openresty/bin/resty
COPY --from=resty /usr/local/openresty/luajit /usr/local/openresty/luajit
COPY --from=resty /usr/local/openresty/lualib /usr/local/openresty/lualib
COPY --from=resty /usr/local/openresty/site/lualib /usr/local/openresty/site/lualib

COPY engine/lib/badsector/geoip_db.lua engine/lib/badsector/geo_lookup.lua /usr/local/openresty/badsector/lib/badsector/

COPY deploy/watcher/watcher.sh deploy/watcher/attack-kernel.sh deploy/watcher/asn-lookup-one.lua /usr/local/bin/
RUN chmod +x /usr/local/bin/watcher.sh /usr/local/bin/attack-kernel.sh /usr/local/bin/asn-lookup-one.lua

CMD ["/usr/local/bin/watcher.sh"]
