#!/usr/bin/env bash

changeDefaultConfig() {
  defaultConfig=/usr/lib/rabbitmq/lib/rabbitmq_server-3.7.17/sbin/rabbitmq-defaults
  #修改config file location
  sed -i "s/\/etc\/rabbitmq\/rabbitmq/\/opt\/app\/conf\/rabbitmq\/rabbitmq/" $defaultConfig
  sed -i "s/\/etc\/rabbitmq\/enabled_plugins/\/opt\/app\/conf\/rabbitmq\/enabled_plugins/" $defaultConfig
  sed -i "s/\/etc/\/data/" $defaultConfig
  sed -i "s/\/var\/lib/\/data/" $defaultConfig
  sed -i "s/\/var\/log\/rabbitmq/\/data\/rabbitmq\/log/" $defaultConfig
}

addNode2Cluster() {
  n1=$(echo $DISC_NODE | awk -F, '{print $1}')
  rabbitmqctl --quiet join_cluster --disc "rabbit@$n1"
}

rabbitmq-server-custom() {
  PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/erlang/bin
  NAME=rabbitmq-server
  DAEMON=/usr/sbin/${NAME}
  CONTROL=/usr/sbin/rabbitmqctl
  DESC=rabbitmq-server
  USER=rabbitmq
  ROTATE_SUFFIX=
  INIT_LOG_DIR=/data/rabbitmq/log
  START_PROG="daemon"
  LOCK_FILE=/var/lock/subsys/$NAME
  test -x $DAEMON || exit 0
  test -x $CONTROL || exit 0
  RETVAL=0
  set -e
  [ -f /etc/default/${NAME} ] && . /etc/default/${NAME}
  [ -f /etc/sysconfig/${NAME} ] && . /etc/sysconfig/${NAME}
  case "$1" in
    start)
        echo -n "Starting $DESC: "
        start_rabbitmq
        echo "$NAME."
        ;;
    stop)
        echo -n "Stopping $DESC: "
        stop_rabbitmq
        echo "$NAME."
        ;;
    status)
        status_rabbitmq
        ;;
    rotate-logs)
        echo -n "Rotating log files for $DESC: "
        rotate_logs_rabbitmq
        ;;
    force-reload|reload|restart)
        echo -n "Restarting $DESC: "
        restart_rabbitmq
        echo "$NAME."
        ;;
    try-restart)
        echo -n "Restarting $DESC: "
        restart_running_rabbitmq
        echo "$NAME."
        ;;
    *)
        echo "Usage: $0 {start|stop|status|rotate-logs|restart|condrestart|try-restart|reload|force-reload}" >&2
        RETVAL=1
        ;;
  esac
  exit $RETVAL
}

start_rabbitmq () {
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

stop_rabbitmq () {
  status_rabbitmq quiet
  if [ $RETVAL = 0 ] ; then
      set +e
      $CONTROL stop
  else
      echo RabbitMQ is not running
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
      echo RabbitMQ is not runnning
      RETVAL=0
  fi
}

restart_rabbitmq() {
  stop_rabbitmq
  start_rabbitmq
}

init() {
  mkdir -p /data/rabbitmq/{log,mnesia,config,schema} 
  chown -R rabbitmq:rabbitmq /data/
  cookie=$(echo $CLUSTER_ID | awk -F - '{print $2}')
  chmod 750 /var/lib/rabbitmq/.erlang.cookie
  echo $cookie >/var/lib/rabbitmq/.erlang.cookie
  chmod 400 /var/lib/rabbitmq/.erlang.cookie
  changeDefaultConfig
  sleep $SID
  rabbitmq-server-custom start
  rabbitmq-plugins enable rabbitmq_stomp
  rabbitmq-plugins enable rabbitmq_web_stomp
  rabbitmq-plugins enable rabbitmq_mqtt
  rabbitmq-plugins enable rabbitmq_web_mqtt
  rabbitmq-plugins enable rabbitmq_management
  rabbitmq-plugins enable rabbitmq_delayed_message_exchange
  rabbitmq-plugins enable rabbitmq_shovel
  rabbitmq-plugins enable rabbitmq_shovel_management
  addNode2Cluster
  if [ "$MY_ROLE" = "ram" ]; then
    init_ram
  fi
  rabbitmqctl  node_health_check >/dev/null  2>&1
  if [ $? -eq 0 ]; then
     rabbitmqctl  add_user  monitor  monitor4rabbitmq
     rabbitmqctl  set_user_tags  monitor  monitoring
     exit 0
   else
      exit 1
  fi
}

start() {
  rabbitmqctl node_health_check >/dev/null  2>&1
  if [ $? -eq 0 ]; then
       exit 0
  fi
  init
  if [ $? -eq 0 ]; then
       echo "Start rabbitmq successful"
       exit 0
      else
      echo "Failed to start rabbitmq" 1>&2
      exit 1
  fi
}


stop() {
  PIDS=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
  if [ -z "$PIDS" ]
  then
    echo "RabbitMQ server is not running" 1>&2
    exit 0
  fi
  rabbitmq-server-custom stop
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
           if [ $? -eq 0 ]; then
               log "Init rabbitmq_ram successful"
               exit 0
             else
               for i in $(seq 0 120); do
                 pid=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
                 kill -9 $pid
                 rm -rf /data/rabbitmq/mnesia*
                 rabbitmq-server-custom start
                 rabbitmqctl stop_app
                 rabbitmqctl change_cluster_node_type ram
                    if [ $? -eq 0 ]; then
                       rabbitmqctl start_app
                       if [ $? -eq 0 ]; then
                       log "Init rabbitmq_ram successful"
                       exit 0
                       fi
                   fi
                 sleep 1s
                 done
           fi
    else
      for i in $(seq 0 120); do
      pid=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
      kill -9 $pid
      rm -rf /data/rabbitmq/mnesia*
      rabbitmq-server-custom start
      rabbitmqctl stop_app
      rabbitmqctl change_cluster_node_type ram
       if [ $? -eq 0 ]; then
             rabbitmqctl start_app
             if [ $? -eq 0 ]; then
             echo "Init rabbitmq_ram successful"
              exit 0
            fi
         fi
       sleep 1s
    done
  fi
  rabbitmqctl  node_health_check >/dev/null  2>&1
  if [ $? -eq 0 ]; then
     exit 0
  else
    sleep 15s
    rabbitmqctl start_app
    if [ $? -eq 0 ]; then
    exit 0
     else 
    exit 1
   fi
  fi
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
       rabbitmq-server-custom start
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

health_check() {
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