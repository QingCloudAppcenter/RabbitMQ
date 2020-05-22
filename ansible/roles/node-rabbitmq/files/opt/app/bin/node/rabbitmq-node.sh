# Error codes
EC_SCALE_OUT_ERR=240
EC_UNHEALTHY=241

checkNodesHealthy() {
  local node; for node in $@; do
    rabbitmqctl -s -n rabbit@${node} node_health_check -t 3 | grep -o passed || return $EC_UNHEALTHY
  done
}

start() {
  local firstDiscNode; firstDiscNode="$(echo ${DISC_NODES} | awk -F/ '{print $2}')";
  if [[ "${HOSTNAME}" != "${firstDiscNode}" ]]; then # wait for first disc node prepare tables
    retry 20 3 0 checkNodesHealthy "${firstDiscNode}"  #the first node not ready now
  fi
  _start
}

setConfFile() {
  mkdir -p /data/{log,mnesia,config,schema}
  chown -R rabbitmq:rabbitmq /data/{log,mnesia,config,schema}
}

initNode() {
  _initNode
  setConfFile
}

reload() {
  if ! isNodeInitialized; then return 0; fi
  case ${1} in
    rabbitmq-server)
      local rabbitmqConfFile="/etc/rabbitmq/rabbitmq.conf";
      if [[ -f ${rabbitmqConfFile}.1 ]] && [[ "$(comm --nocheck-order -23 ${rabbitmqConfFile} ${rabbitmqConfFile}.1 | grep -v  ^cluster_formation)" ]]; then  # only figure out the changed parameter
        _reload rabbitmq-server;
      fi
      ;;
    *)
      _reload $@ ;;
  esac
}

preCheckForScaleIn() {
  local allNodes; allNodes="$(echo "${DISC_NODES}" "${RAM_NODES}"  | xargs -n1 | awk -F/ '{print $2}')";
  checkNodesHealthy "${allNodes}" # there was unhealthy node
}

scaleIn() {
  log "scale in include ${DELETING_HOSTS:-null}"
  local clusterInfo; clusterInfo="$(rabbitmqctl -t 3 cluster_status --formatter=json)";
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
  rabbitmqctl status -t 3 --formatter=json | jq '{"fd_used": (.file_descriptors.total_used), "sockets_used": (.file_descriptors.sockets_used), "proc_used": (.processes.used), "run_queue": (.run_queue), "mem_used": (.memory.total.rss / 1048576)}'
}

addNodeToCluster()  {
  # write for the node which peer discover failed or the adding node
  local firstDiscNode; firstDiscNode="$(echo ${DISC_NODES} | awk -F/ '{print $2}')";
  local clusterInfo; clusterInfo="$(rabbitmqctl -t 3 cluster_status --formatter=json)";
  local allNodes; allNodes="$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]?]')";
  if [[ ! "$allNodes" =~ "${firstDiscNode}" ]]; then  #disc node ${DISC_NODES##*-} was not clustered
    rabbitmqctl stop_app
    rabbitmqctl join_cluster --${MY_ROLE} rabbit@${firstDiscNode}
    rabbitmqctl start_app
  else
    log "${firstDiscNode} already clustered or ${MY_ID} not the adding node."
  fi
}
