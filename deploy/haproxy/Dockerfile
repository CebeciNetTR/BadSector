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
# socat: admin socket'e (stats socket) canli "set/add map" komutlari gondermek icin (restart'siz esik degistirme)
# /var/run/haproxy: admin socket dizini. Container "USER haproxy" ile calistigi icin
# dizin onceden olusturulup haproxy kullanicisina devredilmeli, yoksa socket acilamaz.
RUN apk add --no-cache socat \
    && mkdir -p /var/run/haproxy \
    && chown -R haproxy:haproxy /var/run/haproxy /usr/local/etc/haproxy/maps \
    && cp "/usr/local/etc/haproxy/haproxy-${HAPROXY_CONFIG}.cfg" /usr/local/etc/haproxy/haproxy.cfg \
    && chown haproxy:haproxy /usr/local/etc/haproxy/haproxy.cfg \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

USER haproxy

EXPOSE 9080 80 443

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg", "-db"]
