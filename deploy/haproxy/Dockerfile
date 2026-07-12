FROM haproxy:2.9-alpine

ARG HAPROXY_CONFIG=dev

COPY haproxy-dev.cfg haproxy-live.cfg /usr/local/etc/haproxy/
COPY lua/ /usr/local/etc/haproxy/lua/

USER root
RUN cp "/usr/local/etc/haproxy/haproxy-${HAPROXY_CONFIG}.cfg" /usr/local/etc/haproxy/haproxy.cfg \
    && chown haproxy:haproxy /usr/local/etc/haproxy/haproxy.cfg

USER haproxy

EXPOSE 9080 80 443

CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg", "-db"]
