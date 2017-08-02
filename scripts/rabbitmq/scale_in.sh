#!/bin/bash
delete_disc=$(cat /etc/cluster_info |grep delete_disc=|awk -F = '{print $2}')
oldIFS=$IFS  #定义一个变量为默认IFS
IFS=,        #设置IFS为逗号
for i in $delete_disc
do
 rabbitmqctl forget_cluster_node  $i
done
IFS=$oldIFS  #还原IFS为默认值

delete_ram=$(cat /etc/cluster_info |grep delete_ram=|awk -F = '{print $2}')
oldIFS=$IFS
IFS=,
for i in $delete_ram
do
 rabbitmqctl forget_cluster_node  $i
done
IFS=$oldIFS
rabbitmqctl status
