initNode() {
  _initNode
  mkdir -p /data/haproxy/logs
  chown -R haproxy.haproxy /data/haproxy
  mkdir -p /data/keepalived/logs
  chown -R root.root /data/keepalived
}

checkSvc() {
  checkActive ${1%%/*} || {
    log "Service '$1' is inactive."
    return $EC_CHECK_INACTIVE
  }
  local endpoints=$(echo $1 | awk -F/ '{print $3}')
  local endpoint; for endpoint in ${endpoints//,/ }; do
    checkEndpoint $endpoint || {
      log "Endpoint '$endpoint' is unreachable."
      return 0
    }
  done
}