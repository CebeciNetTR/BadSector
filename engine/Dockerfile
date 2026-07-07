FROM openresty/openresty:1.25.3.1-alpine

RUN apk add --no-cache curl git unzip perl libmaxminddb \
    && ln -sf /usr/lib/libmaxminddb.so.0 /usr/lib/libmaxminddb.so \
    && /usr/local/openresty/bin/opm get anjia0532/lua-resty-maxminddb
RUN mkdir -p /etc/badsector/coraza/rules /etc/badsector/runtime

COPY lib/ /usr/local/openresty/badsector/lib/
COPY conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY coraza/ /etc/badsector/coraza/

RUN /usr/local/openresty/bin/openresty -t

ENV BADSECTOR_RUNTIME=/etc/badsector/runtime

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://127.0.0.1:8080/badsector/health || exit 1

# Foreground nginx (daemon off in nginx.conf). API must be healthy first (sites.json on shared volume).
CMD ["/usr/local/openresty/bin/openresty", "-c", "/usr/local/openresty/nginx/conf/nginx.conf"]
