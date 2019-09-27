#!/usr/bin/env bash
rCtl=/etc/init.d/rabbitmq-server

changeDefaultConfig() {
  defaultConfig=/usr/lib/rabbitmq/lib/rabbitmq_server-3.7.18/sbin/rabbitmq-defaults
  #修改config file location
  sed -i "s/\/etc\/rabbitmq\/rabbitmq/\/opt\/app\/conf\/rabbitmq\/rabbitmq/" $defaultConfig
  sed -i "s/\/etc/\/data/" $defaultConfig
  sed -i "s/\/var\/lib/\/data/" $defaultConfig
  sed -i "s/\/var\/log\/rabbitmq/\/data\/rabbitmq\/log/" $defaultConfig
  sed -i "s/\/data\/rabbitmq\/enabled_plugins/\/etc\/rabbitmq\/enabled_plugins/" $defaultConfig
}

addMonitor() {
  userInfo=$(rabbitmqctl list_users --formatter=json | jq ".[].user")
  if [[ "$userInfo" =~ "monitor" ]]; then
    echo "User monitor already exist." 
  else
    rabbitmqctl node_health_check >/dev/null 2>&1 && {
      rabbitmqctl add_user monitor monitor4rabbitmq
      rabbitmqctl set_user_tags  monitor monitoring
    }
  fi

}

addNode2Cluster() { 
  systemctl restart rabbitmq-server #make sure mq has been started
  addMonitor
#  local nodes=$(rabbitmqctl cluster_status --formatter=json | jq ".nodes.$MY_ROLE[]")
  systemctl restart rabbitmq-server #make sure mnesia is running
  if [[ "$?" -ne 0  ]]; then
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
  echo "finished add node to cluster."
}

start_rabbitmq () {
  _start
  $rCtl start
  scale_out
}

status_rabbitmq() {
  if [ "$1" != "quiet" ] ; then
    rabbitmqctl status 2>&1
  else
    rabbitmqctl status > /dev/null 2>&1
  fi
}

setCookie() {
  mkdir -p /etc/keepalived
  mkdir -p /data/rabbitmq/{log,mnesia,config,schema}
  chown -R rabbitmq:rabbitmq /data/
  cookie=$(echo $CLUSTER_ID | awk -F - '{print $2}')
  chmod 750 /var/lib/rabbitmq/.erlang.cookie
  echo $cookie >/var/lib/rabbitmq/.erlang.cookie
  chmod 400 /var/lib/rabbitmq/.erlang.cookie
}

init_rabbitmq() {
  _init
  systemctl stop rabbitmq-server
  setCookie
#  changeDefaultConfig
  sleep ${SID}
  addNode2Cluster
  if [ "$MY_ROLE" = "ram" ]; then
    init_ram
  fi
}


stop_rabbitmq () {
  PIDS=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
  if [ -z "$PIDS" ];
  then
    echo "RabbitMQ server is not running" 1>&2
    exit 0
  fi
  status_rabbitmq quiet
  if [ $? -eq 0 ]; then
    rabbitmqctl stop
  else
    echo RabbitMQ is not running
  fi
  systemctl stop rabbitmq-server
}

init_ram() {
  rabbitmqctl stop_app
  ramNodeInfo=$(rabbitmqctl cluster_status --formatter=json | jq ".nodes.ram[]")
  if [[ "$ramNodeInfo" =~ "$MY_ID" ]]; then
    t=$(rabbitmqctl change_cluster_node_type ram)
  fi
  if [ $t -eq 0 ]; then
    rabbitmqctl start_app
  else
    systemctl stop rabbitmq-server
    rm -rf /data/rabbitmq/mnesia*
  fi
  $rCtl restart
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
  disc)    role=rabbitmq  ;;
  ram)     role=rabbitmq  ;;
  haproxy) role=extra     ;;
  client)  role=extra     ;;
  *)       echo "error role"
esac

init_extra() {
  setCookie
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
  init_${role}
}

start() {
  start_${role}
}

stop() {
  $rCtl stop
}

restart() {
  $rCtl  restart
}

check() {
  check_${role}
}

update() {
  init
  start
}