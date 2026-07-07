FROM haproxy:2.9-alpine

COPY haproxy-dev.cfg haproxy-live.cfg /usr/local/etc/haproxy/

ENV HAPROXY_CONFIG=dev

# No external entrypoint script — avoids Windows CRLF breaking Alpine builds.
CMD ["/bin/sh", "-c", "if [ \"${HAPROXY_CONFIG:-dev}\" = live ]; then cp /usr/local/etc/haproxy/haproxy-live.cfg /usr/local/etc/haproxy/haproxy.cfg; else cp /usr/local/etc/haproxy/haproxy-dev.cfg /usr/local/etc/haproxy/haproxy.cfg; fi && exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg -db"]
