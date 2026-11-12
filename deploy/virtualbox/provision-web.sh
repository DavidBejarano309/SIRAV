#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/sirav-web-provision.log) 2>&1
install -d -m 0755 /opt/sirav/releases /opt/sirav/bin
install -d -o sirav -g sirav -m 0750 /opt/sirav/evidencias
chmod 0755 /opt/sirav/bin/start-api.sh
systemctl daemon-reload
systemctl enable nginx sirav-api.service
if ! swapon --show | grep -q /swapfile; then
  if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile
    chmod 0600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
printf 'vm.swappiness=10\n' > /etc/sysctl.d/90-sirav.conf
sysctl -w vm.swappiness=10
touch /opt/sirav/web-ready
