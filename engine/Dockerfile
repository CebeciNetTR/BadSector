FROM openresty/openresty:1.25.3.1-alpine

RUN apk add --no-cache curl git unzip perl libmaxminddb \
    && ln -sf /usr/lib/libmaxminddb.so.0 /usr/lib/libmaxminddb.so \
    && /usr/local/openresty/bin/opm get anjia0532/lua-resty-maxminddb
RUN mkdir -p /etc/badsector/coraza/rules /etc/badsector/runtime

COPY lib/ /usr/local/openresty/badsector/lib/
COPY conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY coraza/ /etc/badsector/coraza/

# Startup script is generated inside the image (LF only — no Windows CRLF from git).
RUN cat > /usr/local/bin/badsector-engine-start << 'EOF'
#!/bin/sh
set -e
RT="${BADSECTOR_RUNTIME:-/etc/badsector/runtime}"
S="$RT/sites.json"
echo "badsector-engine: waiting for $S..."
i=0
while [ ! -f "$S" ]; do
  i=$((i + 1))
  if [ "$i" -gt 120 ]; then
    echo "badsector-engine: timeout waiting for sites.json"
    exit 1
  fi
  sleep 1
done
echo "badsector-engine: config ready, starting OpenResty"
exec /usr/local/openresty/bin/openresty -c /usr/local/openresty/nginx/conf/nginx.conf
EOF

RUN /usr/local/openresty/bin/openresty -t

ENV BADSECTOR_RUNTIME=/etc/badsector/runtime

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8080/badsector/health || exit 1

CMD ["/bin/sh", "/usr/local/bin/badsector-engine-start"]
