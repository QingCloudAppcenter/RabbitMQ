# Error codes
EC_SCALE_OUT_ERR=240

start() {
  log " startMQ start"
  [[ "${HOSTNAME}" != "${DISC_NODES:2:10}" ]] && { # wait for first disc node prepare tables
     while [[ ! $(rabbitmqctl --node rabbit@${DISC_NODES:2:10} -s  node_health_check) =~ "passed" ]]; do 
      sleep 2; #the first node not ready now
    done
  } 
  _start
  #retry 2 1 0 initNode
  addNode2Cluster
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

isFileChanged() {
  # 1: true  0: false
  if [[ -f "${1}.1" ]]; then
    cmp -s ${1} ${1}.1
  else
    return 0
  fi
}

checkFileChanged() {
  # 1: 存在且相同  0: 不存在/不同
  ! ([ -f "$1.1" ] && cmp -s $1 $1.1)
}

reload() {
  if ! isNodeInitialized; then return 0; fi
  case ${1} in
    rabbitmq-server)
      if isFileChanged "/opt/app/bin/envs/instance.env"; then
        log "first start or cluster didn't changed"
        [[ "$(comm --nocheck-order -23 /etc/rabbitmq/rabbitmq.conf /etc/rabbitmq/rabbitmq.conf.1 | grep -v  ^cluster_formation | wc -l)" -gt "0" ]] && _reload rabbitmq-server
      else
        log "add node ${ADDINGHOST:-null}, del node ${DELETINGHOST:-null}"
      fi
      ;;
    *) 
      _reload $@ ;;
  esac
}

scale_in() {
  log "scale in include ${DELETINGHOST:-null}"
  local clusterInfo=$(rabbitmqctl cluster_status --formatter=json)
  local allNodes=$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]?]');
  for i in ${DELETINGHOST}; do
    if [[ "$allNodes" =~ "${i}" ]]; then
      rabbitmqctl forget_cluster_node rabbit@${i}
      log "scale_in forget node $i from cluster"
    fi
  done

}

scale_out() {
  if [[ -n "${ADDINGHOST}" ]]; then
    for i in ${ADDINGHOST}; do
      local clusterInfo=$(rabbitmqctl -t 3 cluster_status -n rabbit@${i} --formatter=json | jq -j '[.nodes.disc[], .nodes.ram[]?]')
      if [[ "$(rabbitmqctl -t 3 node_health_check -n rabbit@${i})" =~ "passed" ]] && [[ "${clusterInfo}" =~ "${HOSTNAME}" ]]; then
        log "${i} was clustered successful in scale-out";
      else
        log "${i} was clustering failed in scale-out";
        exit 240
      fi
    done
  fi
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
