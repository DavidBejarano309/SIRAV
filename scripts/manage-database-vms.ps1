param(
  [ValidateSet('Start','Stop','Status','Check','Diagnose','Repair')][string]$Action='Status',
  [ValidateSet('All','Postgres','Mongo')][string]$Machine='All'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$runtime=Join-Path $root '.runtime/virtualbox'
$vbox='C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$machines=@(
  @{ Name='SIRAV-PostgreSQL'; Kind='Postgres'; Ip='192.168.56.21'; Ssh=2221; Port=15432; Container='sirav-postgres' },
  @{ Name='SIRAV-MongoDB'; Kind='Mongo'; Ip='192.168.56.22'; Ssh=2222; Port=17017; Container='sirav-mongo' }
)
foreach ($vm in $machines) {
  if ($Machine -ne 'All' -and $Machine -ne $vm.Kind) { continue }
  $info=(& $vbox showvminfo $vm.Name --machinereadable) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "No se encontro $($vm.Name)" }
  if ($info -match '(?m)^VMState="([^"]+)"') { $state=$matches[1] } else { throw 'Estado desconocido' }
  switch ($Action) {
    'Start' {
      if ($state -eq 'running') { Write-Host "$($vm.Name) ya esta encendida."; continue }
      & $vbox startvm $vm.Name --type headless
      if ($LASTEXITCODE -ne 0) { throw "No pudo arrancar $($vm.Name)" }
    }
    'Stop' {
      if ($state -eq 'running') {
        & $vbox controlvm $vm.Name acpipowerbutton
        if ($LASTEXITCODE -ne 0) { throw 'Fallo la solicitud de apagado' }
        Write-Host "Apagado normal solicitado a $($vm.Name)."
      } else { Write-Host "$($vm.Name): $state" }
    }
    'Status' {
      Write-Host "$($vm.Name): $state | RAM 2048 MB | privada $($vm.Ip) | localhost:$($vm.Port) | SSH $($vm.Ssh)"
    }
    { $_ -in 'Check','Diagnose','Repair' } {
      if ($state -ne 'running') { throw "$($vm.Name) esta apagada" }
      $sshArgs=@('-i','.runtime/virtualbox/id_ed25519','-p',"$($vm.Ssh)",'-o','BatchMode=yes','-o','ConnectTimeout=20','-o','StrictHostKeyChecking=accept-new','-o','UserKnownHostsFile=.runtime/virtualbox/known_hosts','sirav@127.0.0.1')
      $remoteScript=@'
set -e
cloud-init status
if [ ! -f /opt/sirav/provisioned ]; then
  echo 'Inicializacion pendiente; consulta /var/log/cloud-init-output.log'
  exit 3
fi
docker ps --format '{{.Names}}: {{.Status}}'
free -m
ip -4 -brief address show lan0
'@
      if ($vm.Kind -eq 'Postgres') {
        $remoteScript += "`n" + @'
docker exec -i sirav-postgres sh <<'PG'
set -e
export PGPASSWORD="$DB_PASSWORD"
psql -h 127.0.0.1 -U sirav_app -d sirav_3fn -v ON_ERROR_STOP=1 <<'SQL'
SELECT current_user, current_database();
SELECT current_setting('server_version') AS version;
SELECT count(*) AS tablas FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';
SELECT count(*) AS vehiculos FROM vehiculo;
SELECT to_regprocedure('sp_cargar_historial_demo()') AS procedimiento_supuestos;
SQL
PG
'@
      } else {
        $remoteScript += "`n" + @'
docker exec -i sirav-mongo sh <<'MG'
set -e
mongosh --quiet --username sirav_app --password "$MONGO_PASSWORD" --authenticationDatabase sirav_3fn sirav_3fn --eval 'if(db.runCommand({ping:1}).ok!==1) quit(2); print("Base: "+db.getName()+"; version: "+db.version()); printjson(db.getCollectionNames()); printjson(db.inspecciones_vehiculo.getIndexes());'
MG
'@
      }
      if ($Action -eq 'Diagnose') {
        $remoteScript=@'
cloud-init status --long || true
tail -n 70 /var/log/cloud-init-output.log
test ! -f /var/log/sirav-provision.log || tail -n 30 /var/log/sirav-provision.log
systemctl is-active docker ssh.socket ssh.service || true
systemctl --no-pager --full status containerd.service docker.socket docker.service || true
journalctl --no-pager -u containerd.service -u docker.socket -u docker.service -n 50
docker ps -a --format '{{.Names}}: {{.Status}}' || true
ip -4 -brief address
'@
      }
      if ($Action -eq 'Repair') {
        $remoteScript=@'
set -e
if [ -f /opt/sirav/provisioned ]; then
  echo 'La provision ya esta completa; no se repite.'
  exit 0
fi
recovery="/root/sirav-recovery/dpkg-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$recovery"
cp -a /var/lib/dpkg/updates "$recovery/updates-backup"
for update in /var/lib/dpkg/updates/[0-9][0-9][0-9][0-9]; do
  if [ -f "$update" ] && ! grep -aq '^Package: ' "$update"; then
    mv "$update" "$recovery/invalid-$(basename "$update")"
  fi
done
dpkg --configure -a
DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
getent group docker >/dev/null || groupadd --system docker
systemctl reset-failed containerd.service docker.socket docker.service || true
systemctl start containerd.service
systemctl start docker.socket
systemctl enable --now docker.service
docker info >/dev/null
sed -i '/^set -euo pipefail$/a if [ -f /opt/sirav/provisioned ]; then exit 0; fi' /opt/sirav/provision.sh
bash /opt/sirav/provision.sh
cloud-init modules --mode final
'@
      }
      $remoteBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript.Replace("`r`n","`n")+"`n"))
      Push-Location $root
      try {
        & ssh.exe @sshArgs "echo $remoteBase64 | base64 -d | sudo bash"
        if ($LASTEXITCODE -ne 0) { throw "Fallo $Action en $($vm.Name). Consulta -Action Diagnose para revisar los registros." }
      } finally { Pop-Location }
    }
  }
}
