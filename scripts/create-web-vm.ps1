param(
  [string]$VmFolder=(Join-Path $env:USERPROFILE 'VirtualBox VMs'),
  [string]$BridgeAdapter='Intel(R) Wi-Fi 6E AX211 160MHz',
  [string]$HostOnlyAdapter='VirtualBox Host-Only Ethernet Adapter'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$runtime=Join-Path $root '.runtime/virtualbox'
$seedDir=Join-Path $runtime 'SIRAV-Web'
$vbox='C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function VBox { & $vbox @args; if ($LASTEXITCODE -ne 0) { throw "VBoxManage fallo: $($args[0])" } }
function Write-Utf8([string]$Path,[string]$Value) { [IO.File]::WriteAllText($Path,$Value.Replace("`r`n","`n"),(New-Object Text.UTF8Encoding($false))) }
$registered=(& $vbox list vms) -join "`n"
if ($registered -match '"SIRAV-Web"') { throw 'SIRAV-Web ya existe. Se conserva; utiliza deploy-web-vm.ps1 para actualizar la aplicacion.' }
$image=Join-Path $runtime 'ubuntu-24.04-server-cloudimg-amd64.vmdk'
$sumLine=Get-Content (Join-Path $runtime 'SHA256SUMS') | Where-Object { $_ -match ' \*ubuntu-24.04-server-cloudimg-amd64.vmdk$' }
if (!$sumLine -or (Get-FileHash -Algorithm SHA256 -LiteralPath $image).Hash -ne $sumLine.Split(' ')[0]) { throw 'La imagen Ubuntu no coincide con su SHA-256.' }
$access=Get-Content (Join-Path $runtime 'access.json') -Raw | ConvertFrom-Json
$publicKey=(Get-Content (Join-Path $runtime 'id_ed25519.pub') -Raw).Trim()
$values=@{}
foreach ($line in Get-Content (Join-Path $root '.env')) {
  if ($line -match '^([A-Z_]+)=(.*)$') { $values[$matches[1]]=$matches[2].Trim().Trim('"').Trim("'") }
}
foreach ($name in @('DB_PASSWORD','MONGO_PASSWORD','JWT_SECRET')) { if (!$values[$name]) { throw "Falta $name en .env" } }
$mongoPassword=[Uri]::EscapeDataString($values.MONGO_PASSWORD)
$applicationEnv="DB_URL=jdbc:postgresql://192.168.56.21:5432/sirav_3fn`nDB_USER=sirav_app`nDB_PASSWORD=$($values.DB_PASSWORD)`nMONGO_URI=mongodb://sirav_app:${mongoPassword}@192.168.56.22:27017/sirav_3fn?authSource=sirav_3fn`nJWT_SECRET=$($values.JWT_SECRET)`nSEED_DEMO=$($values.SEED_DEMO)`nDEMO_PASSWORD=$($values.DEMO_PASSWORD)`nTZ=America/Bogota`n"
$files=@(
  @{ Path='/opt/sirav/application.env'; Mode='0600'; Text=$applicationEnv },
  @{ Path='/opt/sirav/bin/start-api.sh'; Mode='0755'; Text=[IO.File]::ReadAllText((Join-Path $root 'deploy/virtualbox/start-api.sh')) },
  @{ Path='/opt/sirav/bin/provision-web.sh'; Mode='0755'; Text=[IO.File]::ReadAllText((Join-Path $root 'deploy/virtualbox/provision-web.sh')) },
  @{ Path='/etc/systemd/system/sirav-api.service'; Mode='0644'; Text=[IO.File]::ReadAllText((Join-Path $root 'deploy/virtualbox/sirav-api.service')) }
)
New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
$cloud=@"
#cloud-config
hostname: sirav-web
manage_etc_hosts: true
timezone: America/Bogota
ssh_pwauth: false
disable_root: true
users:
  - name: sirav
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    lock_passwd: false
    ssh_authorized_keys:
      - $publicKey
chpasswd:
  expire: false
  users:
    - name: sirav
      password: $($access.consolePassword)
      type: text
package_update: true
package_upgrade: false
packages: [nginx, openjdk-21-jre-headless, curl]
write_files:
"@
foreach ($file in $files) {
  $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($file.Text.Replace("`r`n","`n")))
  $cloud+="`n  - path: $($file.Path)`n    permissions: '$($file.Mode)'`n    encoding: b64`n    content: $encoded"
}
$cloud+="`nruncmd:`n  - [bash, /opt/sirav/bin/provision-web.sh]`n"
Write-Utf8 (Join-Path $seedDir 'user-data') $cloud
Write-Utf8 (Join-Path $seedDir 'meta-data') "instance-id: sirav-web-v1`nlocal-hostname: sirav-web`n"
Write-Utf8 (Join-Path $seedDir 'network-config') @'
version: 2
ethernets:
  nat:
    match:
      name: enp0s3
    dhcp4: true
    dhcp4-overrides:
      route-metric: 100
  private:
    match:
      macaddress: '08:00:27:a3:23:01'
    set-name: lan0
    dhcp4: false
    addresses: [192.168.56.23/24]
  public:
    match:
      macaddress: '08:00:27:a3:23:02'
    set-name: public0
    dhcp4: true
    optional: true
    dhcp4-overrides:
      route-metric: 600
      use-dns: false
'@
$viso=Join-Path $seedDir 'seed.viso'
$recipe="--iprt-iso-maker-file-marker=$([guid]::NewGuid())`n--volume-id=CIDATA`n--iso-level=3`n--rock-ridge`n"
foreach ($file in @('user-data','meta-data','network-config')) { $recipe+='"/'+$file+'='+(Join-Path $seedDir $file).Replace('\','/')+'"'+"`n" }
Write-Utf8 $viso $recipe
VBox createvm --name SIRAV-Web --ostype Ubuntu_64 --basefolder $VmFolder --register
$info=(& $vbox showvminfo SIRAV-Web --machinereadable) -join "`n"
if ($info -match '(?m)^UUID="([^"]+)"') { Write-Utf8 (Join-Path $seedDir 'created-uuid.txt') $matches[1] }
$disk=Join-Path (Join-Path $VmFolder 'SIRAV-Web') 'system.vdi'
VBox clonemedium disk $image $disk --format VDI
VBox closemedium disk $image
VBox modifymedium disk $disk --resize 20480
VBox modifyvm SIRAV-Web --memory 2048 --cpus 2 --ioapic on --paravirtprovider minimal --hpet on --graphicscontroller vmsvga --vram 16 --audio-enabled off --usb off --boot1 disk --boot2 dvd --boot3 none --boot4 none --nic1 nat --nic2 hostonly --hostonlyadapter2 $HostOnlyAdapter --macaddress2 080027A32301 --nic3 bridged --bridgeadapter3 $BridgeAdapter --macaddress3 080027A32302 --cableconnected1 on --cableconnected2 on --cableconnected3 on
VBox modifyvm SIRAV-Web --natpf1 'ssh,tcp,127.0.0.1,2223,,22' --natpf1 'web,tcp,127.0.0.1,8088,,80'
VBox storagectl SIRAV-Web --name SATA --add sata --controller IntelAhci --portcount 2 --bootable on
VBox storageattach SIRAV-Web --storagectl SATA --port 0 --device 0 --type hdd --medium $disk
VBox storageattach SIRAV-Web --storagectl SATA --port 1 --device 0 --type dvddrive --medium $viso
VBox modifyvm SIRAV-Web --description 'SIRAV Web: Ubuntu Server 24.04 LTS, 2048 MB, 2 vCPU, 20 GB. Nginx + React + API Java. Privada 192.168.56.23; SSH localhost:2223; web localhost:8088; acceso LAN mediante puente Wi-Fi.'
VBox startvm SIRAV-Web --type headless
Write-Host 'SIRAV-Web creada e iniciada. Espera a que cloud-init termine antes de desplegar la aplicacion.'
