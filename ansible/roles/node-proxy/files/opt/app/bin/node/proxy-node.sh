initNode() {
  _initNode
  mkdir -p /data/haproxy/logs
  chown -R haproxy.haproxy /data/haproxy
  mkdir -p /data/keepalived/logs
  chown -R root.root /data/keepalived
}
