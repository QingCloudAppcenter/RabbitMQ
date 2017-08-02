#!/bin/bash
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
