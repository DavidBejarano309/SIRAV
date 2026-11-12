param([ValidateSet('Start','Stop','Status','Check','Diagnose')][string]$Action='Status')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$vbox='C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$info=(& $vbox showvminfo SIRAV-Web --machinereadable) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'SIRAV-Web no existe' }
if ($info -match '(?m)^VMState="([^"]+)"') { $state=$matches[1] } else { throw 'Estado desconocido' }
switch ($Action) {
  'Start' {
    if ($state -eq 'running') { Write-Host 'SIRAV-Web ya esta encendida.'; break }
    & $vbox startvm SIRAV-Web --type headless
    if ($LASTEXITCODE -ne 0) { throw 'No pudo arrancar SIRAV-Web' }
  }
  'Stop' {
    if ($state -eq 'running') { & $vbox controlvm SIRAV-Web acpipowerbutton }
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo solicitar el apagado normal' }
  }
  'Status' { Write-Host "SIRAV-Web: $state | RAM 2048 MB | SSH 2223 | http://localhost:8088 | privada http://192.168.56.23" }
  { $_ -in 'Check','Diagnose' } {
    if ($state -ne 'running') { throw 'SIRAV-Web esta apagada' }
    $remote=@'
set -e
cloud-init status
test -f /opt/sirav/web-ready
systemctl is-active nginx sirav-api.service
curl --fail --silent --max-time 20 http://127.0.0.1/actuator/health
echo
echo 'Direccion para navegadores de la red local:'
ip -4 -o address show public0 | awk '{split($4,a,"/"); print "http://" a[1]}'
free -m
'@
    if ($Action -eq 'Diagnose') {
      $remote=@'
cloud-init status --long || true
tail -n 50 /var/log/cloud-init-output.log
test ! -f /var/log/sirav-web-provision.log || tail -n 30 /var/log/sirav-web-provision.log
systemctl --no-pager --full status nginx sirav-api.service || true
journalctl -u sirav-api.service --no-pager -n 50
ip -4 -brief address
'@
    }
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote.Replace("`r`n","`n")+"`n"))
    Push-Location $root
    try {
      & ssh.exe -i .runtime/virtualbox/id_ed25519 -p 2223 -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=.runtime/virtualbox/known_hosts sirav@127.0.0.1 "echo $encoded | base64 -d | sudo bash"
      if ($LASTEXITCODE -ne 0) { throw "Fallo $Action en SIRAV-Web" }
    } finally { Pop-Location }
  }
}
