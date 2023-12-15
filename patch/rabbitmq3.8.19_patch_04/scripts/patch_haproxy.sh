#!/usr/bin/env bash
rm -f /etc/confd/templates/keepalived.sh.tmpl
cp /patch/keepalived.sh.tmpl /etc/confd/templates/
service confd restart
sleep 2s
systemctl restart keepalived

