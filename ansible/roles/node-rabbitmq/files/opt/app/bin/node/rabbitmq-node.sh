# Error codes
EC_SCALE_OUT_ERR=240

start() {
  log " startMQ start"
  [[ "${HOSTNAME}" != "${DISC_NODES:2:10}" ]] && sleep ${SID} # left 5s for 1 disc node prepare tables
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
  for i in $(curl -s metadata/self/adding-hosts | grep instance_id | awk '{print $2}'); do
    local clusterInfo=$(rabbitmqctl -t 3 cluster_status -n rabbit@${i} --formatter=json | jq -j '[.nodes.disc[], .nodes.ram[]?]')
    if [[ "$(rabbitmqctl -t 3 node_health_check -n rabbit@${i})" =~ "passed" ]] && [[ "${clusterInfo}" =~ "${HOSTNAME}" ]]; then
      log "${i} was clustered successful in scale-out";
    else
      log "${i} was clustering failed in scale-out";
      exit 240
    fi
  done
}

measure() {
  rabbitmqctl status --formatter=json | jq '{"fd_used": (.file_descriptors.total_used), "sockets_used" : (.file_descriptors.sockets_used), "proc_used": (.processes.used), "run_queue": (.run_queue), "mem_used": (.memory.total.rss / 1048576)}'
}

addNode2Cluster()  {
  # write for the node which peer discover failed or the adding node
  local clusterInfo=$(rabbitmqctl cluster_status --formatter=json)
  local allNodes=$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]?]');
  if [[ ! "$allNodes" =~ "${DISC_NODES:2:10}" ]]; then  #disc node ${DISC_NODES##*-} was not clustered
    rabbitmqctl stop_app
    rabbitmqctl join_cluster --${MY_ROLE} rabbit@${DISC_NODES:2:10}
    rabbitmqctl start_app
  else
    log "${DISC_NODES:2:10} already clustered or ${MY_ID} not the adding node."
  fi
}