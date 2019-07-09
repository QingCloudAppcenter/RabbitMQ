init() {
  _init
  mkdir -p /data/{mnesia,log}
  chown -R rabbitmq.svc /data/{mnesia,log}
}

