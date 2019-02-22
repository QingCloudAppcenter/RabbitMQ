#!/bin/bash
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
