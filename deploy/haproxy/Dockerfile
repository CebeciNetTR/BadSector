FROM haproxy:2.9-alpine

ARG HAPROXY_CONFIG=dev

COPY haproxy-dev.cfg haproxy-live.cfg /usr/local/etc/haproxy/
COPY lua/ /usr/local/etc/haproxy/lua/
COPY maps/ /usr/local/etc/haproxy/maps/
# Volume ile golgelense bile entrypoint'in map dosyasini tohumlayabilmesi icin
# varsayilan sablonu ayri (mount edilmeyen) bir konumda da sakla.
COPY maps/ /usr/local/share/badsector/maps-default/
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

USER root
# socat: admin socket; su-exec: entrypoint root iken haproxy'ye dusmek icin
RUN apk add --no-cache socat su-exec \
    && mkdir -p /var/run/haproxy \
    && chown -R haproxy:haproxy /var/run/haproxy /usr/local/etc/haproxy/maps \
    && cp "/usr/local/etc/haproxy/haproxy-${HAPROXY_CONFIG}.cfg" /usr/local/etc/haproxy/haproxy.cfg \
    && chown haproxy:haproxy /usr/local/etc/haproxy/haproxy.cfg \
    && chmod u+w /usr/local/etc/haproxy/haproxy.cfg \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

# Entrypoint root calisir (maps volume + cfg patch); sonra su-exec haproxy.
EXPOSE 9080 80 443

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg", "-db"]
