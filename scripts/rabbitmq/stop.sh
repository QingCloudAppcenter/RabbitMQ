#!/bin/bash
PIDS=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
if [ -z "$PIDS" ]
then
  echo "RabbitMQ server is not running" 1>&2
  exit 0
fi
/opt/bin/rabbitmq-server-custom.sh stop
#check
  loop=60
  force=1
  while [ "$loop" -gt 0 ]
  do
    pid=`ps ax | grep -i 'beam' | grep -v grep| awk '{print $1}'`
    if [ "x$pid" = "x" ]
    then
      force=0
      break
    else
      sleep 3s
      loop=`expr $loop - 1`
    fi
  done
  if [ "$force" -eq 1 ]
  then
   pkill -9 beam
  fi
