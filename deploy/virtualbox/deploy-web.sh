#!/bin/bash
set -euo pipefail
for attempt in $(seq 1 300); do
  test ! -f /opt/sirav/web-ready || break
  sleep 3
done
test -f /opt/sirav/web-ready
command -v curl >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y curl
release="/opt/sirav/releases/$(date +%Y%m%d-%H%M%S)"
install -d -m 0755 "$release"
tar -xf /home/sirav/web-bundle.tar -C "$release"
test -s "$release/frontend/index.html"
test -s "$release/backend/app.jar"
chmod -R a+rX "$release"
ln -sfn "$release" /opt/sirav/current
install -m 0644 "$release/nginx.conf" /etc/nginx/sites-available/sirav
ln -sfn /etc/nginx/sites-available/sirav /etc/nginx/sites-enabled/default
nginx -t
systemctl restart sirav-api.service
systemctl reload nginx
ready=false
for attempt in $(seq 1 300); do
  if curl --fail --silent --max-time 5 http://127.0.0.1/actuator/health | grep -q '"status":"UP"'; then
    ready=true
    break
  fi
  sleep 3
done
if [ "$ready" != true ]; then
  journalctl -u sirav-api.service --no-pager -n 60
  exit 1
fi
echo 'Frontend y API: UP; PostgreSQL y MongoDB conectados.'
ip -4 -brief address show public0
echo 'Acceso privado: http://192.168.56.23 ; desde Windows: http://localhost:8088'
