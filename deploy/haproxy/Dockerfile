FROM haproxy:2.9-alpine
COPY haproxy-dev.cfg haproxy-live.cfg /usr/local/etc/haproxy/
COPY --chmod=755 docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
