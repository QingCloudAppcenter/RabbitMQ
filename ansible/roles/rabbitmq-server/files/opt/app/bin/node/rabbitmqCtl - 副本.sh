#!/usr/bin/env bash
rCtl=/etc/init.d/rabbitmq-server
file_log=/data/appctl/logs/test.log

changeDefaultConfig() {
  defaultConfig=/usr/lib/rabbitmq/lib/rabbitmq_server-3.7.18/sbin/rabbitmq-defaults
  #修改config file location
  sed -i "s/\/etc\/rabbitmq\/rabbitmq/\/opt\/app\/conf\/rabbitmq\/rabbitmq/" $defaultConfig
  sed -i "s/\/etc/\/data/" $defaultConfig
  sed -i "s/\/var\/lib/\/data/" $defaultConfig
  sed -i "s/\/var\/log\/rabbitmq/\/data\/rabbitmq\/log/" $defaultConfig
  sed -i "s/\/data\/rabbitmq\/enabled_plugins/\/etc\/rabbitmq\/enabled_plugins/" $defaultConfig
}

addUserMonitor2Node() {
  echo "addUserMonitor2Node start" >> $file_log
  userInfo=$(rabbitmqctl list_users --formatter=json | jq ".[].user")
  if [[ "$userInfo" =~ "monitor" ]]; then
    echo "User monitor already exist." 
  else
    rabbitmqctl node_health_check >/dev/null 2>&1 && {
      rabbitmqctl add_user monitor monitor4rabbitmq
      rabbitmqctl set_user_tags monitor monitoring
    }
  fi
  echo "addUserMonitor2Node end" >> $file_log
}

addNode2Cluster() {
  echo "addNode2Cluster start" >> $file_log
  systemctl restart rabbitmq-server #make sure mq has been started
  addUserMonitor2Node
#  local nodes=$(rabbitmqctl cluster_status --formatter=json | jq ".nodes.$MY_ROLE[]")
  systemctl restart rabbitmq-server #make sure mnesia is running
  if [[ "$?" -ne 0 ]]; then
    systemctl stop rabbitmq-server ;
    rm -rf /data/rabbitmq/mnesia/* ;
    systemctl start rabbitmq-server
  fi
  rabbitmqctl stop_app > /dev/null 2>&1
  n1=$(echo $DISC_NODE | awk -F, '{print $1}')
  if [[ "$n1" =~ "$HOSTNAME" ]]; then 
    rabbitmqctl start_app > /dev/null 2>&1
  else 
    #n2=$(echo $DISC_NODE | awk -F, '{print $2}'); 
    rabbitmqctl --quiet join_cluster --${MY_ROLE} "rabbit@$n1"
    rabbitmqctl start_app > /dev/null 2>&1
  fi
  echo "finished add node to cluster." >> $file_log
  echo "addNode2Cluster end" >> $file_log
}

startRabbitmq() {
  echo "startRabbitmq start" >> $file_log
  _start
  $rCtl start
  scale_out
  echo "startRabbitmq end" >> $file_log
}

restartRabbitmq() {
  stop
  start
}

statusRabbitmq() {
  if [ "$1" != "quiet" ] ; then
    rabbitmqctl status 2>&1
  else
    rabbitmqctl status > /dev/null 2>&1
  fi
}

setConfFile() {
  echo "setConfFile start" >> $file_log
  mkdir -p /etc/keepalived
  mkdir -p /data/rabbitmq/{log,mnesia,config,schema}
  chown -R rabbitmq:rabbitmq /data/rabbitmq
  echo "setConfFile end" >> $file_log
}

initRabbitmq() {
  echo "initRabbitmq start" >> $file_log
  _init
  systemctl stop rabbitmq-server
  setConfFile
#  changeDefaultConfig
  sleep ${SID}
  addNode2Cluster
  if [ "$MY_ROLE" = "ram" ]; then
    initRam
  fi
  echo "initRabbitmq end" >> $file_log
}


stopRabbitmq () {
  PIDS=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
  if [ -z "$PIDS" ];
  then
    echo "RabbitMQ server is not running" 1>&2
    exit 0
  fi
  statusRabbitmq quiet
  if [ $? -eq 0 ]; then
    rabbitmqctl stop
  else
    echo RabbitMQ is not running
  fi
  systemctl stop rabbitmq-server
}

initRam() {
  echo "initRam start" >> $file_log
  rabbitmqctl stop_app
  ramNodeInfo=$(rabbitmqctl cluster_status --formatter=json | jq ".nodes.disc[]")
  if [[ "$ramNodeInfo" =~ "$MY_ID" ]]; then
    # role=ram, but addnode2cluster failed to join cluster with --ram
    t=$(rabbitmqctl change_cluster_node_type ram)
  fi
  if [ $t -eq 0 ]; then
    rabbitmqctl start_app
  else
    systemctl stop rabbitmq-server
    rm -rf /data/rabbitmq/mnesia*
  fi
  $rCtl restart
  echo "initRam end" >> $file_log
}

scale_in() {
  clusterInfo=$(rabbitmqctl cluster_status --formatter=json)
  #allNodes=$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]]')
  #runningNodes=$(echo $clusterInfo | jq '.running_nodes')
  deleteNodes=$(echo $clusterInfo | jq -c '[(.nodes.disc[], .nodes.ram[])]-[(.running_nodes[])]')
  dn=$(echo $deleteNodes | jq '.[]')
  for i in $dn
  do
    node=$(echo $i | awk -F \" '{print $2}')
    rabbitmqctl forget_cluster_node $node
  done
  rabbitmqctl start_app
}

scale_out() {
  echo "scale_out start" >> $file_log
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
  echo "scale_out end" >> $file_log
}

appMonitor() {
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

checkRabbitmq() {
  rabbitmqctl -t 3 node_health_check >/dev/null  2>&1
  if [ $? -eq 0 ]; then
    exit 0
  else
    rabbitmqctl -t 3 status  >/dev/null  2>&1
    if [ $? -eq 0 ]; then
      exit 1
    else
      exit 2
    fi
  fi
}

case "$MY_ROLE" in
  disc)    role=Rabbitmq  ;;
  ram)     role=Rabbitmq  ;;
  haproxy) role=Extra     ;;
  client)  role=Extra     ;;
  *)       echo "error role"
esac

initExtra() {
  echo "init_extra start" >> $file_log
  setConfFile
  _init
  if [ "$MY_ROLE" = "client" ]; then echo 'root:rabbitmq' | chpasswd; echo 'ubuntu:rabbitmq' | chpasswd; fi
    echo "init_extra end" >> $file_log
}

startExtra() {
  _start
}

stopExtra() {
  _stop
}

restartExtra() {
  _restart
}

checkExtra() {
  _check
}

init() {
  systemctl daemon-reload
  init${role}
  echo "init end" >> $file_log
}

start() {
  start${role}
}

stop() {
  stop${role}
}

restart() {
  restart${role}
}

check() {
  check${role}
}

update() {
  init
  start
}