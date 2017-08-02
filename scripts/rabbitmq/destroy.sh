#!/bin/bash
rabbitmqctl stop_app
#meta_ip=$(cat /etc/confd/confd.toml |grep nodes |awk -F  [ '{print $2}' |awk -F , '{print $1}' |awk -F \' '{print $2}')
#result=$(curl $meta_ip/self/deleting-hosts -s)
#if [ "$result" = "Not found"  ]; then
#     exit 0
#   else
#    rabbitmqctl  -t 120 reset
#     cd /data
#     rm -rf mnesia*
#     exit 0
# fi
