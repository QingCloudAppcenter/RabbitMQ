#!/bin/bash
hosts=$(cat /etc/cluster_info |grep hosts=|awk -F = '{print $2}' |awk -F , '{print $1}')
sed -i 's/localhost/'$hosts'/g' /root/rabbitmqadmin
