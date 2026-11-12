param([Parameter(Mandatory=$true)][string]$Settings,[ValidateSet('Start','Check','Stop','Diagnose')][string]$Action='Check')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json
if ($config.Database -notmatch '^sirav_audit_[0-9]{14}$') { throw 'Solo se permite una base aislada de auditoria.' }
$database=$config.Database
$unit='sirav-audit-'+$database
Push-Location $root
try {
  if ($Action -eq 'Start') {
    $stage=Join-Path $config.RunDirectory ('web-stage-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'frontend'),(Join-Path $stage 'backend') | Out-Null
    Copy-Item -Path frontend/dist/* -Destination (Join-Path $stage 'frontend') -Recurse
    Copy-Item -LiteralPath backend/target/sirav-api-1.0.0.jar -Destination (Join-Path $stage 'backend/app.jar')
    $bundle=Join-Path $config.RunDirectory 'audit-web.tar'
    & tar.exe -cf $bundle -C $stage .
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar la aplicacion de auditoria' }
    & scp.exe -i .runtime/virtualbox/id_ed25519 -P 2223 -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.runtime/virtualbox/known_hosts $bundle "sirav@127.0.0.1:audit-$database.tar"
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar la aplicacion de auditoria' }
    $envText="DB_URL=$($config.DB_URL.Replace('//127.0.0.1:15432/','//192.168.56.21:5432/'))`nDB_USER=$($config.DB_USER)`nDB_PASSWORD=$($config.DB_PASSWORD)`nMONGO_URI=$($config.MONGO_URI.Replace('@127.0.0.1:17017/','@192.168.56.22:27017/'))`nJWT_SECRET=$($config.JWT_SECRET)`nSEED_DEMO=true`nDEMO_PASSWORD=$($config.DEMO_PASSWORD)`nTZ=America/Bogota`n"
    $envEncoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($envText))
    $nginx=[IO.File]::ReadAllText((Join-Path $root 'frontend/nginx.conf')).Replace('listen 80;','listen 8089;').Replace('http://backend:8080','http://127.0.0.1:8081').Replace('/usr/share/nginx/html',"/opt/sirav/audit/$database/frontend")
    $nginx="# Audit database: $database`n"+$nginx
    $nginxEncoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($nginx.Replace("`r`n","`n")))
    $remote=@'
set -euo pipefail
base=/opt/sirav/audit/__DATABASE__
test ! -f /etc/nginx/conf.d/sirav-audit.conf
if ss -ltn | grep -q ':8081 '; then echo 'El puerto 8081 ya esta ocupado'; exit 1; fi
install -d -m 0755 "$base"
tar -xf /home/sirav/audit-__DATABASE__.tar -C "$base"
chmod -R a+rX "$base"
install -d -o sirav -g sirav -m 0750 "$base/evidencias"
echo __ENV__ | base64 -d > "$base/application.env"
address=$(ip -4 -o address show public0 | awk '{split($4,a,"/");print a[1]}')
printf '\nCORS_ORIGIN=http://localhost:8089,http://127.0.0.1:8089,http://192.168.56.23:8089,http://%s:8089\nEVIDENCE_DIRECTORY=%s/evidencias\n' "$address" "$base" >> "$base/application.env"
chmod 0600 "$base/application.env"
echo __NGINX__ | base64 -d > /etc/nginx/conf.d/sirav-audit.conf
nginx -t
systemd-run --collect --unit=__UNIT__ --property=User=sirav --property=Group=sirav --property=MemoryMax=700M --property=WorkingDirectory="$base" --property=EnvironmentFile="$base/application.env" /usr/bin/java -Xms64m -Xmx384m -XX:MaxMetaspaceSize=160m -jar "$base/backend/app.jar" --server.port=8081 --server.address=127.0.0.1
systemctl reload nginx
for attempt in $(seq 1 300); do
  if curl --fail --silent --max-time 5 http://127.0.0.1:8089/actuator/health | grep -q '"status":"UP"'; then
    echo "Auditoria disponible: http://$address:8089"
    exit 0
  fi
  sleep 3
done
journalctl -u __UNIT__ --no-pager -n 60
exit 1
'@
    $remote=$remote.Replace('__ENV__',$envEncoded).Replace('__NGINX__',$nginxEncoded)
  } elseif ($Action -eq 'Stop') {
    $remote=@'
set -euo pipefail
systemctl stop __UNIT__ || true
if [ -f /etc/nginx/conf.d/sirav-audit.conf ]; then
  grep -qF '# Audit database: __DATABASE__' /etc/nginx/conf.d/sirav-audit.conf
  mv /etc/nginx/conf.d/sirav-audit.conf /opt/sirav/audit/__DATABASE__/nginx-completed.conf
  nginx -t
  systemctl reload nginx
fi
echo 'Servicio de auditoria detenido; datos y evidencias conservados.'
'@
  } elseif ($Action -eq 'Diagnose') {
    $remote="systemctl --no-pager --full status $unit; journalctl -u $unit --no-pager -n 60; free -m; ip -4 -brief address"
  } else {
    $remote="systemctl is-active $unit; curl --fail --silent --max-time 20 http://127.0.0.1:8089/actuator/health; echo"
  }
  $remote=$remote.Replace('__DATABASE__',$database).Replace('__UNIT__',$unit)
  $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote.Replace("`r`n","`n")))
  & ssh.exe -i .runtime/virtualbox/id_ed25519 -p 2223 -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.runtime/virtualbox/known_hosts sirav@127.0.0.1 "echo $encoded | base64 -d | sudo bash"
  if ($LASTEXITCODE -ne 0) { throw "Fallo $Action de la web de auditoria" }
} finally { Pop-Location }
