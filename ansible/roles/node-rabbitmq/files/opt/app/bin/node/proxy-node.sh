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
  log "INFO: Application initialization completed  . "
}

reload() {
  log "INFO: Application is asked to reload  . "
  _reload $@ 
  log "INFO: Application reloaded completely . "
}