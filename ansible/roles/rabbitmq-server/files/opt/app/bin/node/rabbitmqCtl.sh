#!/usr/bin/env bash

changeDefaultConfig() {
  defaultConfig=/usr/lib/rabbitmq/lib/rabbitmq_server-3.7.17/sbin/rabbitmq-defaults
  #修改config file location
  sed -i "s/\/etc\/rabbitmq\/rabbitmq/\/opt\/app\/conf\/rabbitmq\/rabbitmq/" $defaultConfig
  sed -i "s/\/etc/\/data/" $defaultConfig
  sed -i "s/\/var\/lib/\/data/" $defaultConfig
  sed -i "s/\/var\/log\/rabbitmq/\/data\/rabbitmq\/log/" $defaultConfig
  sed -i "s/\/data\/rabbitmq\/enabled_plugins/\/etc\/rabbitmq\/enabled_plugins/" $defaultConfig
}

addNode2Cluster() {
  rabbitmqctl stop_app
  n1=$(echo $DISC_NODE | awk -F, '{print $1}')
  rabbitmqctl --quiet join_cluster --disc "rabbit@$n1"
  rabbitmqctl start_app
}

start_rabbitmq () {
  _start
  rabbitmqctl start_app
  scale_out
  status_rabbitmq quiet
  if [ $RETVAL = 0 ] ; then
      log "RabbitMQ is currently running"
  else
    # RABBIT_NOFILES_LIMIT from /etc/sysconfig/rabbitmq-server is not handled
    # automatically
    if [ "$RABBITMQ_NOFILES_LIMIT" ]; then
      ulimit -n $RABBITMQ_NOFILES_LIMIT
    fi
    systemctl restart rabbitmq-server
  fi
}

status_rabbitmq() {
  set +e
  if [ "$1" != "quiet" ] ; then
      $CONTROL status 2>&1
  else
      $CONTROL status > /dev/null 2>&1
  fi
  if [ $? != 0 ] ; then
      RETVAL=3
  fi
  set -e
}

rotate_logs_rabbitmq() {
  set +e
  $CONTROL rotate_logs ${ROTATE_SUFFIX}
  if [ $? != 0 ] ; then
      RETVAL=1
  fi
  set -e
}

restart_running_rabbitmq () {
  status_rabbitmq quiet
  if [ $RETVAL = 0 ] ; then
      restart_rabbitmq
  else
      echo "RabbitMQ is not runnning"
      RETVAL=0
  fi
}

restart_rabbitmq() {
  stop_rabbitmq
  start_rabbitmq
}

init_rabbitmq() {
  _init
  mkdir -p /data/rabbitmq/{log,mnesia,config,schema}
  chown -R rabbitmq:rabbitmq /data/
  cookie=$(echo $CLUSTER_ID | awk -F - '{print $2}')
  chmod 750 /var/lib/rabbitmq/.erlang.cookie
  echo $cookie >/var/lib/rabbitmq/.erlang.cookie
  chmod 400 /var/lib/rabbitmq/.erlang.cookie
  changeDefaultConfig
  sleep $SID
  systemctl restart rabbitmq-server
  rabbitmq-plugins --quiet enable rabbitmq_stomp
  rabbitmq-plugins --quiet enable rabbitmq_web_stomp
  rabbitmq-plugins --quiet enable rabbitmq_mqtt
  rabbitmq-plugins --quiet enable rabbitmq_web_mqtt
  rabbitmq-plugins --quiet enable rabbitmq_management
  rabbitmq-plugins --quiet enable rabbitmq_delayed_message_exchange
  rabbitmq-plugins --quiet enable rabbitmq_shovel
  rabbitmq-plugins --quiet enable rabbitmq_shovel_management
  addNode2Cluster
  if [ "$MY_ROLE" = "ram" ]; then
    init_ram
  fi
  rabbitmqctl start_app
  rabbitmqctl node_health_check >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    rabbitmqctl add_user monitor monitor4rabbitmq
    rabbitmqctl set_user_tags  monitor monitoring
    exit 0
  else
    exit 1
  fi
}


stop_rabbitmq () {
  PIDS=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
  if [ -z "$PIDS" ]
  then
    echo "RabbitMQ server is not running" 1>&2
    exit 0
  fi
  status_rabbitmq quiet
  if [ $RETVAL = 0 ] ; then
      set +e
      $CONTROL stop
  else
      echo RabbitMQ is not running
  fi
  #check
  loop=60
  force=1
  while [ "$loop" -gt 0 ]
  do
    pid=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
    if [ "x$pid" = "x" ]
    then
      force=0
      break
    else
      sleep 3s
      loop=`expr $loop - 1`
    fi
  done
  if [ "$force" -eq 1 ]
  then
   pkill -9 beam
  fi

}

init_ram() {
  rabbitmqctl stop_app
  rabbitmqctl change_cluster_node_type ram
  if [ $? -eq 0 ]; then
    rabbitmqctl start_app
  else
    rabbitmqctl stop_app
    systemctl stop rabbitmq-server
    pid=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
    kill -9 $pid
    rm -rf /data/rabbitmq/mnesia*
  fi
  systemctl restart rabbitmq-server
  rabbitmqctl start_app
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
  rabbitmqctl status
}

scale_out() {
  rabbitmqctl -t 3 node_health_check >/dev/null  2>&1
  if [ $? -eq 0 ]; then
      exit 0
  else
      rabbitmqctl -t 3 status  >/dev/null  2>&1
      if [ $? -eq 0 ]; then
       rabbitmqctl start_app
     else
       start
     fi
  fi
}

MQ_monitor() {
  data=$(curl -i -u monitor:monitor4rabbitmq "http://localhost:15672/api/nodes/rabbit@$HOSTNAME" -s |tail -1  |jq -r '{mem_alarm: .mem_alarm, disk_free_alarm: .disk_free_alarm,fd_used:.fd_used,sockets_used:.sockets_used,proc_used:.proc_used,run_queue:.run_queue,mem_used:.mem_used}')
  if [ "$data" = "{\"error\":\"not_authorised\",\"reason\":\"Login failed\"}" ]
  then
      log "func MQ_monitor Login failed"
      exit 1
   fi
   if [ "$data" = "{\"error\":\"Object Not Found\",\"reason\":\"Not Found\"}" ]
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

check_rabbitmq() {
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
  disc) role=rabbitmq ;;
  ram) role=rabbitmq ;;
  haproxy) role=extra ;;
  client) role=extra ;;
  *) echo "error role"
esac

init_extra() {
  _init
  if [ "$MY_ROLE" = "client" ]; then echo 'root:rabbitmq' | chpasswd; echo 'ubuntu:rabbitmq' | chpasswd; fi
}

start_extra() {
  _start
}

stop_extra() {
  _stop
}

restart_extra() {
  _restart
}

check_extra() {
  _check
}

init() {
  systemctl daemon-reload
  init_$role
}

start() {
  start_$role
}

stop() {
  stop_$role
}

restart() {
  restart_$role
}

check() {
  check_$role
}

update() {
  init
  start
}