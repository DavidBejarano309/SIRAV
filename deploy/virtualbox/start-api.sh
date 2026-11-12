#!/bin/bash
set -euo pipefail
export CORS_ORIGIN='http://localhost:8088,http://127.0.0.1:8088'
for address in $(ip -o -4 address show scope global | awk '{print $4}' | cut -d/ -f1); do
  CORS_ORIGIN+=",http://$address"
done
export SERVER_ADDRESS=127.0.0.1
export EVIDENCE_DIRECTORY=/opt/sirav/evidencias
exec /usr/bin/java -Xms128m -Xmx512m -XX:MaxMetaspaceSize=192m -jar /opt/sirav/current/backend/app.jar
