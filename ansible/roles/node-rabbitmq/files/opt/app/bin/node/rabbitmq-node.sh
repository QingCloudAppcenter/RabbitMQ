# Error codes
EC_MEASURE_ERR=300



addMonitorUser() {
  log " addMonitorUser start"
  local userInfo
  userInfo=$(rabbitmqctl list_users --formatter=json | jq ".[].user")
  log " $userInfo"
  if [[ "$userInfo" =~ "monitor" ]]; then
    log " User monitor already exist."
  else
    rabbitmqctl add_user monitor monitor4rabbitmq
    rabbitmqctl set_user_tags monitor monitoring
    log " success add user monitor to node."
  fi
  log " addMonitorUser end"
}

start() {
  log " startMQ start"
  [[ "${HOSTNAME}" != "${DISC_NODE:2:10}" ]] && sleep ${SID} # left 5s for 1 disc node prepare tables
  retry 5 2 0 _start
  #retry 2 1 0 initNode
  retry 3 5 0 addNode2Cluster
  log " startMQ end"
}


setConfFile() {
  log " setConfFile start"
  mkdir -p /data/{log,mnesia,config,schema}
  chown -R rabbitmq:rabbitmq /data/{log,mnesia,config,schema}
  log " setConfFile end"
}

initNode() {
  log " initRabbitmq start"
  _initNode
  setConfFile
  log " initRabbitmq end"
}


scale_in() {
  local clusterInfo
  clusterInfo=$(rabbitmqctl cluster_status --formatter=json)
  #allNodes=$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]]')
  #runningNodes=$(echo $clusterInfo | jq '.running_nodes')
  local deleteNodes=$(echo $clusterInfo | jq -c '[(.nodes.disc[], .nodes.ram[]?)]-[(.running_nodes[])]')
  local dn=$(echo $deleteNodes | jq '.[]')
  for i in $dn
  do
    local node=$(echo $i | awk -F \" '{print $2}')
    rabbitmqctl forget_cluster_node $node
    sed -i -e "s/'rabbit@${node}'//g" -e "s/\[\,/\[/g" -e "s/\,\]/\]/g" -e "s/\,\,/\,/g"  /data/mnesia/rabbit@${HOSTNAME}/cluster_nodes.config
  done
  rabbitmqctl start_app
}

scale_out() {
  log " scale_out start"
  rabbitmqctl -t 3 node_health_check >/dev/null  2>&1
  if [ $? -eq 0 ]; then
    exit 0
  else
    rabbitmqctl -t 3 status  >/dev/null  2>&1
    if [ $? -eq 0 ]; then
      rabbitmqctl start_app
    else
      init
      systemctl restart rabbitmq-server
    fi
  fi
  log " scale_out end"
}

measure() {
  data=$(curl --connect-timeout 2 -m 2 -i -u monitor:monitor4rabbitmq "http://localhost:15672/api/nodes/rabbit@$HOSTNAME" -s |tail -1  |jq -r '{mem_alarm: .mem_alarm, disk_free_alarm: .disk_free_alarm,fd_used:.fd_used,sockets_used:.sockets_used,proc_used:.proc_used,run_queue:.run_queue,mem_used:.mem_used}')
  if [[ "$data" =~ "Login failed" ]];
  then
      log "USER monitor Login failed"
      appctl addMonitorUser
      exit 300
  fi
  if [ "$data" = "{\"error\":\"Object Not Found\",\"reason\":\"Not Found\"}" ];
  then
    log "func MQ_monitor Url not found"
    exit 301
  fi
  fd_used=`echo ${data} | jq .'fd_used'`
  sockets_used=`echo ${data} | jq .'sockets_used'`
  proc_used=`echo ${data} | jq .'proc_used'`
  run_queue=`echo ${data} | jq .'run_queue'`
  mem_used=`echo ${data} | jq .'mem_used'`
  mem_used=`gawk -v x=${mem_used} -v y=1048576 'BEGIN{printf "%.0f\n",x/y}'`
  echo "{\"fd_used\":$fd_used,\"sockets_used\":$sockets_used,\"proc_used\":$proc_used,\"run_queue\":$run_queue,\"mem_used\":$mem_used}"

}

initCluster() {
  addMonitorUser
}

addNode2Cluster()  {
  # write for the node which peer discover failed or the adding node
  local clusterInfo=$(rabbitmqctl cluster_status --formatter=json)
  local allNodes=$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]?]');
  if [[ ! "$allNodes" =~ "${DISC_NODE:2:10}" ]]; then  #disc node ${DISC_NODE##*-} was not clustered
    rabbitmqctl stop_app
    rabbitmqctl join_cluster --${MY_ROLE} rabbit@${DISC_NODE:2:10}
    rabbitmqctl start_app
  else
    log "${DISC_NODE:2:10} already clustered or ${MY_ID} not the adding node."
  fi
}