#!/usr/bin/env bash
action() {
  /opt/bin/rabbitmq-server-custom.sh stop
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
      sleep 1s
      loop=`expr $loop - 1`
    fi
  done
  if [ "$force" -eq 1 ]
  then
    pkill -9 beam
  fi
  /opt/bin/rabbitmq-server-custom.sh start
  if [ $? -eq 0 ]; then
      echo "Restart RabbitMQ server successful"
      for i in $(seq 0 15); do
       rabbitmqctl node_health_check
         if [ $? -eq 0 ]; then
         exit 0
         fi
         sleep 1
         done
         rabbitmqctl force_boot
      exit 0
    else
      echo "Failed to restart RabbitMQ server" 1>&2
      exit 1
  fi

}

destroy() {
  rabbitmqctl stop_app
}

get-monitor() {
  data=$(curl -i -u monitor:monitor4rabbitmq "http://localhost:15672/api/nodes/rabbit@$HOSTNAME" -s |tail -1  |jq -r '{mem_alarm: .mem_alarm, disk_free_alarm: .disk_free_alarm,fd_used:.fd_used,sockets_used:.sockets_used,proc_used:.proc_used,run_queue:.run_queue,mem_used:.mem_used}')
  if [ "$data" = "{\"error\":\"not_authorised\",\"reason\":\"Login failed\"}" ]
  then
      echo "Login failed" > /dev/null 2>&1
      exit 1
   fi
   if [ "$data" = "{\"error\":\"Object Not Found\",\"reason\":\"Not Found\"}" ]
   then
       echo "Url not found" > /dev/null 2>&1
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

init() {
  cd /data
  mkdir -p log/old_logs
  chown -R rabbitmq:rabbitmq /data/
  cookie=$(cat /etc/cluster_info |grep cluster_id=|awk -F = '{print $2}')
  chmod 750 /var/lib/rabbitmq/.erlang.cookie
  echo $cookie >/var/lib/rabbitmq/.erlang.cookie
  chmod 400 /var/lib/rabbitmq/.erlang.cookie
  sid=$(cat /etc/cluster_info |grep sid=|awk -F = '{print $2}')
  sleep $sid
  /opt/bin/rabbitmq-server-custom.sh start
  rabbitmq-plugins enable rabbitmq_stomp
  rabbitmq-plugins enable rabbitmq_web_stomp
  rabbitmq-plugins enable rabbitmq_mqtt
  rabbitmq-plugins enable rabbitmq_web_mqtt
  rabbitmq-plugins  enable  rabbitmq_management
  rabbitmqctl  node_health_check >/dev/null  2>&1
  if [ $? -eq 0 ]; then
     rabbitmqctl  add_user  monitor  monitor4rabbitmq
     rabbitmqctl  set_user_tags  monitor  monitoring
     exit 0
   else
      exit 1
  fi
  
}

init_disc() {
  cd /data
  mkdir -p log/old_logs
  chown -R rabbitmq:rabbitmq /data/
  cookie=$(cat /etc/cluster_info |grep cluster_id=|awk -F = '{print $2}')
  chmod 750 /var/lib/rabbitmq/.erlang.cookie
  echo $cookie >/var/lib/rabbitmq/.erlang.cookie
  chmod 400 /var/lib/rabbitmq/.erlang.cookie
  sid=$(cat /etc/cluster_info |grep sid=|awk -F = '{print $2}')
  sleep $sid
  /opt/bin/rabbitmq-server-custom.sh start
  rabbitmq-plugins enable rabbitmq_stomp
  rabbitmq-plugins enable rabbitmq_web_stomp
  rabbitmq-plugins enable rabbitmq_mqtt
  rabbitmq-plugins enable rabbitmq_web_mqtt
  rabbitmq-plugins  enable  rabbitmq_management
  rabbitmq-plugins enable rabbitmq_delayed_message_exchange
  rabbitmq-plugins enable rabbitmq_shovel
  rabbitmq-plugins enable rabbitmq_shovel_management
  rabbitmqctl  node_health_check >/dev/null  2>&1
  if [ $? -eq 0 ]; then
     rabbitmqctl  add_user  monitor  monitor4rabbitmq
     rabbitmqctl  set_user_tags  monitor  monitoring
     exit 0
   else
      exit 1
  fi
  
}

init_ram() {
  cd /data
  mkdir -p log/old_logs
  chown -R rabbitmq:rabbitmq /data/
  cookie=$(cat /etc/cluster_info |grep cluster_id=|awk -F = '{print $2}')
  chmod 750 /var/lib/rabbitmq/.erlang.cookie
  echo $cookie >/var/lib/rabbitmq/.erlang.cookie
  chmod 400 /var/lib/rabbitmq/.erlang.cookie
  /opt/bin/rabbitmq-server-custom.sh start
  rabbitmq-plugins enable rabbitmq_stomp
  rabbitmq-plugins enable rabbitmq_web_stomp
  rabbitmq-plugins enable rabbitmq_mqtt
  rabbitmq-plugins enable rabbitmq_web_mqtt
  rabbitmq-plugins  enable  rabbitmq_management
  rabbitmq-plugins enable rabbitmq_shovel
  rabbitmq-plugins enable rabbitmq_shovel_management
  sid=$(cat /etc/cluster_info |grep sid=|awk -F = '{print $2}')
  sleep $sid
  rabbitmqctl stop_app
  rabbitmqctl change_cluster_node_type ram
  if [ $? -eq 0 ]; then
           rabbitmqctl start_app
           if [ $? -eq 0 ]; then
               echo "Init rabbitmq_ram successful"
               exit 0
             else
               for i in $(seq 0 120); do
                    pid=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
                    kill -9 $pid
                    cd /data
                    rm -rf mnesia*
                   /opt/bin/rabbitmq-server-custom.sh start
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
    else
      for i in $(seq 0 120); do
       pid=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
      kill -9 $pid
      cd /data
      rm -rf mnesia*
      /opt/bin/rabbitmq-server-custom.sh start
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

ensure_pid_dir () {
    PID_DIR=`dirname ${PID_FILE}`
    if [ ! -d ${PID_DIR} ] ; then
        mkdir -p ${PID_DIR}
        chown -R ${USER}:${USER} ${PID_DIR}
        chmod 755 ${PID_DIR}
    fi
}
remove_pid () {
    rm -f ${PID_FILE}
    rmdir `dirname ${PID_FILE}` || :
}
start_rabbitmq () {
    status_rabbitmq quiet
    if [ $RETVAL = 0 ] ; then
        echo RabbitMQ is currently running
    else
        RETVAL=0
        # RABBIT_NOFILES_LIMIT from /etc/sysconfig/rabbitmq-server is not handled
        # automatically
        if [ "$RABBITMQ_NOFILES_LIMIT" ]; then
                ulimit -n $RABBITMQ_NOFILES_LIMIT
        fi
        ensure_pid_dir
        set +e
        RABBITMQ_PID_FILE=$PID_FILE $START_PROG $DAEMON \
            >> "${INIT_LOG_DIR}/startup_log" \
            2>> "${INIT_LOG_DIR}/startup_err" \
            0<&- &
        $CONTROL wait $PID_FILE >/dev/null 2>&1
        RETVAL=$?
        set -e
        case "$RETVAL" in
            0)
                echo SUCCESS
                if [ -n "$LOCK_FILE" ] ; then
                    touch $LOCK_FILE
                fi
                exit 0
                ;;
            *)
                remove_pid
                echo FAILED - check ${INIT_LOG_DIR}/startup_\{log, _err\}
                RETVAL=1
                exit 1
                ;;
        esac
    fi
}
stop_rabbitmq () {
    status_rabbitmq quiet
    if [ $RETVAL = 0 ] ; then
        set +e
        $CONTROL stop ${PID_FILE} > ${INIT_LOG_DIR}/shutdown_log 2> ${INIT_LOG_DIR}/shutdown_err
        RETVAL=$?
        set -e
        if [ $RETVAL = 0 ] ; then
            remove_pid
            if [ -n "$LOCK_FILE" ] ; then
                rm -f $LOCK_FILE
            fi
            exit 0
        else
            echo FAILED - check ${INIT_LOG_DIR}/shutdown_log, _err
            exit 1
        fi
    else
        echo RabbitMQ is not running
        RETVAL=0
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

rabbitmq-server-custom() {
. /etc/init.d/functions
PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/erlang/bin
NAME=rabbitmq-server
DAEMON=/usr/sbin/${NAME}
CONTROL=/usr/sbin/rabbitmqctl
DESC=rabbitmq-server
USER=rabbitmq
ROTATE_SUFFIX=
INIT_LOG_DIR=/data/log
PID_FILE=/var/run/rabbitmq/pid
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

restart() {
PIDS=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
if [ -z "$PIDS" ]
then
  echo "RabbitMQ server is not running" 1>&2
  exit 0
fi
/opt/bin/rabbitmq-server-custom.sh stop
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
  /opt/bin/rabbitmq-server-custom.sh start
  if [ $? -eq 0 ]; then
      echo "Restart RabbitMQ server successful"
      for i in $(seq 0 15); do
       rabbitmqctl node_health_check
         if [ $? -eq 0 ]; then
         exit 0
         fi
         sleep 1
         done
         rabbitmqctl force_boot
      exit 0
    else
      echo "Failed to restart RabbitMQ server" 1>&2
      exit 1
fi
}

scale_in() {
delete_disc=$(cat /etc/cluster_info |grep delete_disc=|awk -F = '{print $2}')
oldIFS=$IFS  #定义一个变量为默认IFS
IFS=,        #设置IFS为逗号
for i in $delete_disc
do
 rabbitmqctl forget_cluster_node  $i
done
IFS=$oldIFS  #还原IFS为默认值

delete_ram=$(cat /etc/cluster_info |grep delete_ram=|awk -F = '{print $2}')
oldIFS=$IFS
IFS=,
for i in $delete_ram
do
 rabbitmqctl forget_cluster_node  $i
done
IFS=$oldIFS
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
     /opt/bin/rabbitmq-server-custom.sh start
   fi
fi

}
start() {
rabbitmqctl node_health_check >/dev/null  2>&1
if [ $? -eq 0 ]; then
     exit 0
fi
cookie=$(cat /etc/cluster_info |grep cluster_id=|awk -F = '{print $2}')
chmod 750 /var/lib/rabbitmq/.erlang.cookie
echo $cookie >/var/lib/rabbitmq/.erlang.cookie
chmod 400 /var/lib/rabbitmq/.erlang.cookie
/opt/bin/rabbitmq-server-custom.sh stop
/opt/bin/rabbitmq-server-custom.sh start
rabbitmq-plugins enable rabbitmq_stomp
rabbitmq-plugins enable rabbitmq_web_stomp
rabbitmq-plugins enable rabbitmq_mqtt
rabbitmq-plugins enable rabbitmq_web_mqtt
rabbitmq-plugins  enable  rabbitmq_management
rabbitmq-plugins enable rabbitmq_delayed_message_exchange
rabbitmq-plugins enable rabbitmq_shovel
rabbitmq-plugins enable rabbitmq_shovel_management
if [ $? -eq 0 ]; then
     echo "Start rabbitmq successful"
     exit 0
    else
    echo "Failed to start rabbitmq" 1>&2
    exit 1
fi

}

start_disc() {
rabbitmqctl node_health_check >/dev/null  2>&1
if [ $? -eq 0 ]; then
     exit 0
fi
cookie=$(cat /etc/cluster_info |grep cluster_id=|awk -F = '{print $2}')
chmod 750 /var/lib/rabbitmq/.erlang.cookie
echo $cookie >/var/lib/rabbitmq/.erlang.cookie
chmod 400 /var/lib/rabbitmq/.erlang.cookie
/opt/bin/rabbitmq-server-custom.sh stop
/opt/bin/rabbitmq-server-custom.sh start
rabbitmq-plugins enable rabbitmq_stomp
rabbitmq-plugins enable rabbitmq_web_stomp
rabbitmq-plugins enable rabbitmq_mqtt
rabbitmq-plugins enable rabbitmq_web_mqtt
rabbitmq-plugins  enable  rabbitmq_management
rabbitmq-plugins enable rabbitmq_delayed_message_exchange
rabbitmq-plugins enable rabbitmq_shovel
rabbitmq-plugins enable rabbitmq_shovel_management
if [ $? -eq 0 ]; then
     echo "Start rabbitmq successful"
     exit 0
    else
    echo "Failed to start rabbitmq" 1>&2
    exit 1
fi

}

start_ram() {
rabbitmqctl node_health_check >/dev/null  2>&1
if [ $? -eq 0 ]; then
     exit 0
fi
cookie=$(cat /etc/cluster_info |grep cluster_id=|awk -F = '{print $2}')
chmod 750 /var/lib/rabbitmq/.erlang.cookie
echo $cookie >/var/lib/rabbitmq/.erlang.cookie
chmod 400 /var/lib/rabbitmq/.erlang.cookie
/opt/bin/rabbitmq-server-custom.sh stop
/opt/bin/rabbitmq-server-custom.sh start
rabbitmq-plugins enable rabbitmq_stomp
rabbitmq-plugins enable rabbitmq_web_stomp
rabbitmq-plugins enable rabbitmq_mqtt
rabbitmq-plugins enable rabbitmq_web_mqtt
rabbitmq-plugins  enable  rabbitmq_management
rabbitmq-plugins enable rabbitmq_shovel
rabbitmq-plugins enable rabbitmq_shovel_management
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
/opt/bin/rabbitmq-server-custom.sh stop
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