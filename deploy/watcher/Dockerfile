FROM alpine:3.19
RUN apk add --no-cache bash redis ipset iptables tzdata curl maxminddb-tools
COPY watcher.sh attack-kernel.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/watcher.sh /usr/local/bin/attack-kernel.sh
CMD ["/usr/local/bin/watcher.sh"]
