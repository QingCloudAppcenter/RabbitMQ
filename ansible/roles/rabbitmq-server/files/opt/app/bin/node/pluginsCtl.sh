#!/usr/bin/env bash

setConfFile() {
  log " `date` setConfFile start"
  mkdir -p /data/{log,mnesia,config,schema}
  chown -R rabbitmq:rabbitmq /data/{log,mnesia,config,schema}
  systemctl daemon-reload
  log " `date` setConfFile end"
}

init() {
  mkdir -p /data/appctl/logs
  log "`date` init_extra start"
  setConfFile
  _init
  if [ "$MY_ROLE" = "client" ]; then
    systemctl unmask ssh; systemctl restart ssh;
    echo 'root:rabbitmq' | chpasswd; echo 'ubuntu:rabbitmq' | chpasswd; 
  fi
  log "`date` init_extra end"
}

start() {
  init
  _start
  appctl restart
}

update() {
  init
  start
}