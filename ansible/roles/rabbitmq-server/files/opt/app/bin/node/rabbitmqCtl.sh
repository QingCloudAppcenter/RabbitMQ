#!/usr/bin/env bash

addUserMonitor2Node() {
  log "`date` addUserMonitor2Node start"
  local userInfo=$(rabbitmqctl list_users --formatter=json | jq ".[].user")
  log "`date` $userInfo"
  if [[ "$userInfo" =~ "monitor" ]]; then
    log "`date` User monitor already exist."
  else
    rabbitmqctl add_user monitor monitor4rabbitmq
    rabbitmqctl set_user_tags monitor monitoring
    log "`date` success add user monitor to node."
  fi
  log "`date` addUserMonitor2Node end"
}

start() {
  log "`date` startMQ start"
  retry 5 2 0 _start
  addUserMonitor2Node
  log "`date` startMQ end"
}


setConfFile() {
  log "`date` setConfFile start"
  mkdir -p /data/{log,mnesia,config,schema}
  chown -R rabbitmq:rabbitmq /data/{log,mnesia,config,schema}
  systemctl daemon-reload
  log "`date` setConfFile end"
}

init() {
  log "`date` initRabbitmq start"
  _init
  if [[ "$MY_ROLE" = "ram" ]]; then
    #remove plugins from ram node
    sed -i "s/rabbitmq_delayed_message_exchange,//" /etc/rabbitmq/enabled_plugins
  fi
  systemctl stop rabbitmq-server
  setConfFile
  log "`date` initRabbitmq end"
}


scale_in() {
  local clusterInfo=$(rabbitmqctl cluster_status --formatter=json)
  #allNodes=$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]]')
  #runningNodes=$(echo $clusterInfo | jq '.running_nodes')
  local deleteNodes=$(echo $clusterInfo | jq -c '[(.nodes.disc[], .nodes.ram[])]-[(.running_nodes[])]')
  local dn=$(echo $deleteNodes | jq '.[]')
  for i in $dn
  do
    local node=$(echo $i | awk -F \" '{print $2}')
    rabbitmqctl forget_cluster_node $node
  done
  rabbitmqctl start_app
}

scale_out() {
  log "`date` scale_out start"
  rabbitmqctl -t 3 node_health_check >/dev/null  2>&1
  if [ $? -eq 0 ]; then
    exit 0
  else
    rabbitmqctl -t 3 status  >/dev/null  2>&1
    if [ $? -eq 0 ]; then
      rabbitmqctl start_app
    else
      init
      systemctl restart rabbitmq-server
    fi
  fi
  log "`date` scale_out end"
}

measure() {
  data=$(curl -i -u monitor:monitor4rabbitmq "http://localhost:15672/api/nodes/rabbit@$HOSTNAME" -s |tail -1  |jq -r '{mem_alarm: .mem_alarm, disk_free_alarm: .disk_free_alarm,fd_used:.fd_used,sockets_used:.sockets_used,proc_used:.proc_used,run_queue:.run_queue,mem_used:.mem_used}')
  if [ "$data" = "{\"error\":\"not_authorised\",\"reason\":\"Login failed\"}" ];
  then
      log "func MQ_monitor Login failed"
      exit 1
  fi
  if [ "$data" = "{\"error\":\"Object Not Found\",\"reason\":\"Not Found\"}" ];
  then
    log "func MQ_monitor Url not found"
    exit 1
  fi
  fd_used=`echo ${data} | jq .'fd_used'`
  sockets_used=`echo ${data} | jq .'sockets_used'`
  proc_used=`echo ${data} | jq .'proc_used'`
  run_queue=`echo ${data} | jq .'run_queue'`
  mem_used=`echo ${data} | jq .'mem_used'`
  mem_used=`gawk -v x=${mem_used} -v y=1048576 'BEGIN{printf "%.0f\n",x/y}'`
  echo "{\"fd_used\":$fd_used,\"sockets_used\":$sockets_used,\"proc_used\":$proc_used,\"run_queue\":$run_queue,\"mem_used\":$mem_used}"

}

update() {
  init
  start
}