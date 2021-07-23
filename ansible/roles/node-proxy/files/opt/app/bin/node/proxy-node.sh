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

stop() {
  log "INFO: Application is asked to stop . "
  _stop || (log "ERROR: services in Node ${MY_INSTANCE_ID} failed to stop  . " && return 1)
  log "INFO: Application stopped successfully  . "
}

start() {
  log "INFO: Application is asked to start . "
  _start || (log "ERROR: services in Node ${MY_INSTANCE_ID} failed to start  . " && return 1)
  log "INFO: Application started successfully  . "
}

initNode() {
  log "INFO: Application is about to initialize . "
  _initNode || ( log "ERROR: Application failed to initialize . " && return 1 )
  mkdir -p /data/haproxy/logs
  chown -R haproxy.haproxy /data/haproxy
  mkdir -p /data/keepalived/logs
  chown -R root.root /data/keepalived
  log "INFO: Application initialization completed  . "
}

reload() {
  log "INFO: Application is asked to reload  . "
  _reload $@
  log "INFO: Application reloaded completely . "
}