# Error codes
EC_SCALE_OUT_ERR=240
EC_UNHEALTHY=241

checkNodesHealthy() {
  local node; for node in $@; do
    rabbitmqctl -s -n rabbit@${node} node_health_check -t 3 | grep -o passed || return $EC_UNHEALTHY
  done
}

checkOnlyLastNodeRunning() {
  # DO NOT USE this epecial func untill u known what will happen
  local runningNodes; runningNodes="$(rabbitmqctl -t 3 cluster_status --formatter=json | jq -j .running_nodes[])";
  case "${#runningNodes}" in
  17) [[ "${runningNodes}" =~ "$@" ]] || return 1 ;;
   0) return 0 ;;
   *) return 1 ;;
  esac
}

stop() {
  #https://www.rabbitmq.com/clustering.html#restarting
  #the last node to go down is the only one that didn't have any running peers at the time of shutdown.
  #sometimes the last node to stop must be the first node to be started after the upgrade.
  local firstDiscNode; firstDiscNode="$(echo ${DISC_NODES} | awk -F/ '{print $2}')";
  if [[ "${MY_INSTANCE_ID}" =~ "${firstDiscNode}" ]]; then
      retry 20 3 0 checkOnlyLastNodeRunning "${MY_INSTANCE_ID}" #notice checkNodesRunning return
  fi
  _stop
}

start() {
  local firstDiscNode; firstDiscNode="$(echo ${DISC_NODES} | awk -F/ '{print $2}')";
  if [[ "${MY_INSTANCE_ID}" != "${firstDiscNode}" ]]; then # wait for first disc node prepare tables
    retry 20 3 0 checkNodesHealthy "${firstDiscNode}"
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
  case "${1}" in
    rabbitmq-server)
      local rabbitmqConfFile="/etc/rabbitmq/rabbitmq.conf";
      if test -f ${rabbitmqConfFile}.1 && ! (diff -q -I "^cluster_formation"  ${rabbitmqConfFile} ${rabbitmqConfFile}.1 ) ; then
        # only figure out the changed parameter
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
  local clusterInfo; clusterInfo="$(rabbitmqctl -t 3 cluster_status --formatter=json)";
  local allNodes; allNodes="$(echo $clusterInfo | jq -j '[.nodes.disc[], .nodes.ram[]?]')";
  local delNode; for delNode in ${DELETING_HOSTS}; do
    if [[ "$allNodes" =~ "${delNode}" ]]; then
      log "node ${delNode} clustered with ${MY_INSTANCE_ID}";
    else
      return $EC_UNHEALTHY
    fi
  done
}

scaleIn() {
  log "scale in include ${DELETING_HOSTS:-null}"
  local delNode; for delNode in ${DELETING_HOSTS}; do
    rabbitmqctl forget_cluster_node rabbit@${delNode};
    log "scale_in forget node ${delNode} from cluster";
  done
}

scaleOut() {
  if [[ -n "${ADDING_HOSTS}" ]]; then
    local joinNode; for joinNode in ${ADDING_HOSTS}; do
      local clusterInfo; clusterInfo="$(rabbitmqctl -t 3 cluster_status -n rabbit@${joinNode} --formatter=json | jq -j '[.nodes.disc[], .nodes.ram[]?]')";
      if checkNodesHealthy "${joinNode}" && [[ "${clusterInfo}" =~ "${MY_INSTANCE_ID}" ]]; then
        log "${joinNode} was clustered successful in scale-out";
      else
        log "${joinNode} was clustering failed in scale-out";
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
    log "${firstDiscNode} already clustered or ${MY_INSTANCE_ID} not the adding node."
  fi
}
