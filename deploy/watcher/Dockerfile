FROM alpine:3.19
RUN apk add --no-cache bash redis ipset iptables tzdata
COPY watcher.sh /usr/local/bin/watcher.sh
RUN chmod +x /usr/local/bin/watcher.sh
CMD ["/usr/local/bin/watcher.sh"]
