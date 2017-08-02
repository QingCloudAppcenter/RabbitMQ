#!/bin/bash
cookie=$(cat /etc/cluster_info |grep cluster_id=|awk -F = '{print $2}')
chmod 750 /var/lib/rabbitmq/.erlang.cookie
echo $cookie >/var/lib/rabbitmq/.erlang.cookie
chmod 400 /var/lib/rabbitmq/.erlang.cookie
