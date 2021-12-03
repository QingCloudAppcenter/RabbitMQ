#!/usr/bin/env bash
rm -f /usr/bin/appctl
rm -f /opt/app/bin/ctl.sh
cp /patch/ctl.sh.bak /opt/app/bin/ctl.sh
ln -s /opt/app/bin/ctl.sh /usr/bin/appctl
chmod 777 /opt/app/bin/ctl.sh /usr/bin/appctl
cp /patch/rabbitmq-server.sh.tmpl.bak /etc/confd/templates/rabbitmq-server.sh.tmpl
service confd restart
