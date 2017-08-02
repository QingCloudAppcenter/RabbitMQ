#!/bin/bash
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

