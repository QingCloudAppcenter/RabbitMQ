initNode() {
  _init

  mkdir -p /data/haproxy/logs
  chown -R haproxy.haproxy /data/haproxy

  mkdir -p /data/keepalived/logs
  chown -R keepalived.keepalived /data/keepalived
}