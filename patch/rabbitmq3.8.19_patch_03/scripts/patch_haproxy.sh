#!/usr/bin/env bash
rm -f /etc/confd/templates/haproxy.sh.tmpl
cp /patch/haproxy.sh.tmpl /etc/confd/templates/
service confd restart
sleep 2s
systemctl restart haproxy

