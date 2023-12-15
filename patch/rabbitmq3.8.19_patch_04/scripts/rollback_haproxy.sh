#!/bin/bash
rm -f /etc/confd/templates/keepalived.sh.tmpl
cp /patch/keepalived.sh.tmpl.bak /etc/confd/templates/keepalived.sh.tmpl
service confd restart
sleep 2s
systemctl restart keepalived
