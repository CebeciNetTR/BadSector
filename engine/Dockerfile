FROM openresty/openresty:1.25.3.1-alpine

RUN apk add --no-cache curl git unzip perl libmaxminddb \
    && ln -sf /usr/lib/libmaxminddb.so.0 /usr/lib/libmaxminddb.so \
    && /usr/local/openresty/bin/opm get anjia0532/lua-resty-maxminddb
RUN mkdir -p /etc/badsector/coraza/rules /etc/badsector/runtime

COPY lib/ /usr/local/openresty/badsector/lib/
COPY conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY coraza/ /etc/badsector/coraza/
COPY docker-entrypoint.sh /docker-entrypoint.sh

ENV BADSECTOR_RUNTIME=/etc/badsector/runtime

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8080/badsector/health || exit 1

ENTRYPOINT ["sh", "/docker-entrypoint.sh"]
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
