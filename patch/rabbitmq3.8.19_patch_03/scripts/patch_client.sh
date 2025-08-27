#!/usr/bin/env bash
rm -f /etc/confd/templates/appctl.sh.tmpl
cp /patch/appctl.sh.tmpl /etc/confd/templates/
rm -f /usr/bin/appctl
rm -f /opt/app/bin/ctl.sh
cp /patch/ctl.sh /opt/app/bin/ctl.sh
ln -s /opt/app/bin/ctl.sh /usr/bin/appctl
chmod 777 /usr/bin/appctl
service confd restart
appctl start 
