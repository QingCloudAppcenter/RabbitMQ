#!/bin/bash
rm -f /etc/confd/templates/haproxy.sh.tmpl
cp /patch/haproxy.sh.tmpl.bak /etc/confd/templates/haproxy.sh.tmpl
service confd restart
sleep 2s
systemctl restart haproxy
