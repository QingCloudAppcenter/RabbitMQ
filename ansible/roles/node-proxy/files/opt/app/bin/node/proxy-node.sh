initNode() {
  _initNode

  mkdir -p /data/haproxy/logs
  chown -R haproxy.haproxy /data/haproxy
  mkdir -p /opt/app/conf/haproxy
  chown -R haproxy.haproxy /opt/app/conf/haproxy

  mkdir -p /data/keepalived/logs
  chown -R root.root /data/keepalived
}

start() {
  retry 5 1 0_start
}