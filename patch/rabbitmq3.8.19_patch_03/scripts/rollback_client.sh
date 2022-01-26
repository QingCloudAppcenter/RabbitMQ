#!/bin/bash
rm -f /etc/confd/templates/appctl.sh.tmpl
cp /patch/appctl.sh.tmpl.bak /etc/confd/templates/appctl.sh.tmpl
rm -f /usr/bin/appctl
rm -f /opt/app/bin/ctl.sh
cp /patch/ctl.sh.bak /opt/app/bin/ctl.sh
ln -s /opt/app/bin/ctl.sh /usr/bin/appctl
service confd restart
sleep 2s
systemctl restart haproxy
