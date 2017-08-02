#!/bin/bash
rabbitmqctl node_health_check >/dev/null  2>&1
if [ $? -eq 0 ]; then
     exit 0
fi
/opt/bin/rabbitmq-server-custom.sh stop
/opt/bin/rabbitmq-server-custom.sh start
if [ $? -eq 0 ]; then
     echo "Start rabbitmq successful"
     exit 0
    else
    echo "Failed to start rabbitmq" 1>&2
    exit 1
fi
