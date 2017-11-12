#!/bin/bash
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
rabbitmq-plugins enable rabbitmq_tracing
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
