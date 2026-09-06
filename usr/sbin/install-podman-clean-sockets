#!/bin/bash

cat <<EOF > /etc/systemd/system/podman-clean-sockets.service
[Unit]
Description=Cleanup stale Podman sockets in /var/pods
DefaultDependencies=no
Before=basic.target

[Service]
Type=oneshot
# Deletes all files in any 'run' subdirectory under /var/pods
ExecStart=/usr/bin/find /var/pods -type d -name run -exec sh -c 'rm -rf -- "$1"/*' _ {} \;
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF
