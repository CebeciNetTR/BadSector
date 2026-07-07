FROM haproxy:2.9-alpine

ARG HAPROXY_CONFIG=dev

COPY haproxy-dev.cfg haproxy-live.cfg /usr/local/etc/haproxy/
RUN cp "/usr/local/etc/haproxy/haproxy-${HAPROXY_CONFIG}.cfg" /usr/local/etc/haproxy/haproxy.cfg

EXPOSE 9080 80 443

CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg", "-db"]
