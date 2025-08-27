#!/usr/bin/env bash
rm -f /usr/bin/appctl
rm -f /opt/app/bin/ctl.sh
cp /patch/ctl.sh /opt/app/bin/ctl.sh
ln -s /opt/app/bin/ctl.sh /usr/bin/appctl
chmod 777 /usr/bin/appctl
systemctl enable rabbitmq-server
systemctl enable caddy

