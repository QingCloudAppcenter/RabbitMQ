#!/bin/bash
hosts=$(cat /etc/cluster_info |grep hosts=|awk -F = '{print $2}' |awk -F , '{print $1}')
sed -i 's/.*default_options = {.*/default_options = { "hostname"        : "'$hosts'",/' /root/rabbitmqadmin
