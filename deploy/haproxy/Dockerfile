FROM haproxy:2.9-alpine
COPY haproxy-dev.cfg haproxy-live.cfg /usr/local/etc/haproxy/
COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["sh", "/docker-entrypoint.sh"]
