#!/bin/bash
rm -f /usr/bin/appctl
rm -f /opt/app/bin/ctl.sh
cp /patch/ctl.sh.bak /opt/app/bin/ctl.sh
ln -s /opt/app/bin/ctl.sh /usr/bin/appctl
