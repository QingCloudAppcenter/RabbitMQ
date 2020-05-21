# Error codes
EC_SCALE_OUT_ERR=240
EC_UNHEALTHY=241

checkNodeHealthy() {
  local node; for node in $@; do
    rabbitmqctl -s -n rabbit@${node} node_health_check -t 3 | grep -o passed || return $EC_UNHEALTHY
  done
}


start() {
  local firstDiscNode; firstDiscNode="$(echo ${DISC_NODES} | awk -F/ '{print $2}')";
  if [[ "${HOSTNAME}" != "${firstDiscNode}" ]]; then # wait for first disc node prepare tables
    retry 20 3 0 checkNodeHealthy "${firstDiscNode}"  #the first node not ready now
  fi
  _start
  #retry 2 1 0 initNode
}


setConfFile() {
  mkdir -p /data/{log,mnesia,config,schema}
  chown -R rabbitmq:rabbitmq /data/{log,mnesia,config,schema}
}

initNode() {
  _initNode
  setConfFile
}


checkFileChanged() {
  #   0: changed,   1: $1 not exsit or not changed
  ! ( [[ ! -f "${1}.1" ]] || cmp -s "${1}" "${1}.1")
}

reload() {
  if ! isNodeInitialized; then return 0; fi
  case ${1} in
    rabbitmq-server)
      local rabbitmqConfFile="/etc/rabbitmq/rabbitmq.conf";
      if [[ -f ${rabbitmqConfFile}.1 ]]; then  # only figure out the changed parameter
        [[ "$(comm --nocheck-order -23 ${rabbitmqConfFile} ${rabbitmqConfFile}.1 | grep -v  ^cluster_formation | wc -l)" -gt "0" ]] && _reload rabbitmq-server 
      fi
      ;;
    *) 
      _reload $@ ;;
  esac
}

preCheckForScaleIn() {
  local clusterInfo; clusterInfo="$(rabbitmqctl cluster_status --formatter=json)";
  local unRunningNode; unRunningNode="$(echo $clusterInfo | jq -c '[(.nodes.disc[], .nodes.ram[]?)]-[(.running_nodes[])]')";
  if [[ "${unRunningNode}" =~ "rabbit" ]]; then return $EC_UNHEALTHY; fi # there was unhealthy node
}

scaleIn() {
  log "scale in include ${DELETING_HOSTS:-null}"
  local clusterInfo; clusterInfo="$(rabbitmqctl cluster_status --formatter=json)";
  local allNodes; allNodes="$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]?]')";
  local i; for i in ${DELETING_HOSTS}; do
    if [[ "$allNodes" =~ "${i}" ]]; then
      rabbitmqctl forget_cluster_node rabbit@${i};
      log "scale_in forget node $i from cluster";
    fi
  done

}

scaleOut() {
  if [[ -n "${ADDING_HOSTS}" ]]; then
    local i; for i in ${ADDING_HOSTS}; do
      local clusterInfo; clusterInfo="$(rabbitmqctl -t 3 cluster_status -n rabbit@${i} --formatter=json | jq -j '[.nodes.disc[], .nodes.ram[]?]')";
      if [[ "$(rabbitmqctl -t 3 node_health_check -n rabbit@${i})" =~ "passed" ]] && [[ "${clusterInfo}" =~ "${HOSTNAME}" ]]; then
        log "${i} was clustered successful in scale-out";
      else
        log "${i} was clustering failed in scale-out";
        return ${EC_SCALE_OUT_ERR}
      fi
    done
  fi
}

measure() {
  rabbitmqctl status --formatter=json | jq '{"fd_used": (.file_descriptors.total_used), "sockets_used": (.file_descriptors.sockets_used), "proc_used": (.processes.used), "run_queue": (.run_queue), "mem_used": (.memory.total.rss / 1048576)}'
}

addNodeToCluster()  {
  # write for the node which peer discover failed or the adding node
  local firstDiscNode; firstDiscNode="$(echo ${DISC_NODES} | awk -F/ '{print $2}')";
  local clusterInfo; clusterInfo="$(rabbitmqctl cluster_status --formatter=json)";
  local allNodes; allNodes="$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]?]')";
  if [[ ! "$allNodes" =~ "${firstDiscNode}" ]]; then  #disc node ${DISC_NODES##*-} was not clustered
    rabbitmqctl stop_app
    rabbitmqctl join_cluster --${MY_ROLE} rabbit@${firstDiscNode}
    rabbitmqctl start_app
  else
    log "${firstDiscNode} already clustered or ${MY_ID} not the adding node."
  fi
}
