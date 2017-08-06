#!/bin/bash
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
if [ $? -eq 0 ]; then
     echo "Start rabbitmq successful"
     exit 0
    else
    echo "Failed to start rabbitmq" 1>&2
    exit 1
fi
