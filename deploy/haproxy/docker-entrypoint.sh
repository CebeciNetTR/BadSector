#!/bin/sh
set -e

CFG="${HAPROXY_CONFIG:-dev}"
case "$CFG" in
  live)
    cp /usr/local/etc/haproxy/haproxy-live.cfg /usr/local/etc/haproxy/haproxy.cfg
    ;;
  *)
    cp /usr/local/etc/haproxy/haproxy-dev.cfg /usr/local/etc/haproxy/haproxy.cfg
    ;;
esac

exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg -db
