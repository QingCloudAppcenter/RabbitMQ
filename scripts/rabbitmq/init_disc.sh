#!/bin/bash
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
rabbitmqctl  node_health_check >/dev/null  2>&1
if [ $? -eq 0 ]; then
   rabbitmqctl  add_user  monitor  monitor4rabbitmq
   rabbitmqctl  set_user_tags  monitor  monitoring
   exit 0
 else
    exit 1
fi
