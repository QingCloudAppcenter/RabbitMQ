#!/usr/bin/env bash
rCtl=/etc/init.d/rabbitmq-server
appctlExcuteLog=/data/appctl/logs/appExcuteLog.log

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
  echo `date`  "addUserMonitor2Node start" >> $appctlExcuteLog
  userInfo=$(rabbitmqctl list_users --formatter=json | jq ".[].user")
  echo `date` "$userInfo" >> $appctlExcuteLog
  if [[ "$userInfo" =~ "monitor" ]]; then
    echo `date`  "User monitor already exist." >> $appctlExcuteLog
  else
    rabbitmqctl add_user monitor monitor4rabbitmq
    rabbitmqctl set_user_tags monitor monitoring
    echo `date` "success add user monitor to node." >> $appctlExcuteLog
  fi
  echo "`date` addUserMonitor2Node end" >> $appctlExcuteLog
}

addNode2Cluster() {
  echo `date` "addNode2Cluster start" >> $appctlExcuteLog
  local flag=1
  while [[ "$flag" = "1" ]]; do
    systemctl restart rabbitmq-server #make sure mq has been started
    if [[ "$?" = "0" ]]; then
      flag=0
    else
      let t=3 ** [${SID}-1]
      sleep $t
    fi
  done
  addUserMonitor2Node
  echo `date` "addNode2Cluster end" >> $appctlExcuteLog
}

startRabbitmq() {
  echo `date` "startRabbitmq start" >> $appctlExcuteLog
  _start
  $rCtl start
  scale_out
  echo `date` "startRabbitmq end" >> $appctlExcuteLog
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
  echo `date` "setConfFile start" >> $appctlExcuteLog
  sed -i "s/\/etc\/haproxy\/haproxy.cfg/\/opt\/app\/conf\/haproxy-KP\/haproxy.cfg/" /lib/systemd/system/haproxy.service
  mkdir -p /etc/keepalived
  mkdir -p /data/{log,mnesia,config,schema}
  chown -R rabbitmq:rabbitmq /data/{log,mnesia,config,schema}
  systemctl daemon-reload
  echo `date` "setConfFile end" >> $appctlExcuteLog
}

initRabbitmq() {
  echo `date` "initRabbitmq start" >> $appctlExcuteLog
  _init
  if [[ "$MY_ROLE" = "ram" ]]; then 
    sed -is "s/rabbitmq_delayed_message_exchange,//" /etc/rabbitmq/enabled_plugins
  fi
  systemctl stop rabbitmq-server
  setConfFile
#  changeDefaultConfig
  sleep ${SID}
  addNode2Cluster
  if [[ "$MY_ROLE" = "ram" ]]; then
    initRam
  fi
  echo `date` "initRabbitmq end" >> $appctlExcuteLog
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
  echo `date` "initRam start" >> $appctlExcuteLog
  ramNodeInfo=$(rabbitmqctl cluster_status --formatter=json | jq ".nodes.disc[]")
  rabbitmqctl stop_app > /dev/null 2>&1
  echo `date` "initRam cluster-disc-node ::: $ramNodeInfo" >> $appctlExcuteLog
  if [[ "$ramNodeInfo" =~ "$MY_ID" ]]; then
    # role=ram, but addnode2cluster failed to join cluster with --ram
    n1=$(echo $DISC_NODE | awk -F, '{print $1}')
    rabbitmqctl --quiet join_cluster --ram "rabbit@$n1"
  fi
  rabbitmqctl start_app
  if [[ "$?" > "0" ]]; then
    systemctl restart rabbitmq-server
  fi
  echo `date` "initRam end" >> $appctlExcuteLog
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
  echo `date` "scale_out start" >> $appctlExcuteLog
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
  echo `date` "scale_out end" >> $appctlExcuteLog
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
  echo `date` "init_extra start" >> $appctlExcuteLog
  setConfFile
  _init
  if [ "$MY_ROLE" = "client" ]; then
    systemctl unmask ssh; systemctl restart ssh;
    echo 'root:rabbitmq' | chpasswd; echo 'ubuntu:rabbitmq' | chpasswd; 
  fi
  echo `date` "init_extra end" >> $appctlExcuteLog
}

startExtra() {
  _start
  appctl restart
}

stopExtra() {
  _stop
}

restartExtra() {
  _restart
}

checkExtra() {
  _check
#  local svc; for svc in $(getServices); do 
#    systemctl is-active  -q  ${svc%%/*}
#    if [[ "$?" > "0" ]]; then
#      exit 1;
#    fi
#  done
}

init() {
  mkdir -p /data/appctl/logs
  init${role}
  echo `date` "init end" >> $appctlExcuteLog
}

start() {
  if [ -f "/data/appctl/logs/appExcuteLog.log" ]; then 
    echo `date` "app inited" >> $appctlExcuteLog
  else
    appctl init
  fi
  systemctl daemon-reload
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