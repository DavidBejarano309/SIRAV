param(
  [string]$VmFolder = (Join-Path $env:USERPROFILE 'VirtualBox VMs'),
  [string]$HostOnlyAdapter = 'VirtualBox Host-Only Ethernet Adapter'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root '.runtime/virtualbox'
$vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function VBox { & $vbox @args; if ($LASTEXITCODE -ne 0) { throw "VBoxManage fallo: $($args[0])" } }
function Write-Utf8([string]$Path, [string]$Value) {
  [IO.File]::WriteAllText($Path, $Value.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
}
function New-Secret {
  $bytes = New-Object byte[] 24
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$image = Join-Path $runtime 'ubuntu-24.04-server-cloudimg-amd64.vmdk'
$sums = Join-Path $runtime 'SHA256SUMS'
if (!(Test-Path -LiteralPath $sums) -or !(Test-Path -LiteralPath $image)) {
  & curl.exe --fail --silent --show-error --location --retry 2 --output $sums https://cloud-images.ubuntu.com/releases/noble/release/SHA256SUMS
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo descargar la lista oficial de SHA-256' }
  & curl.exe --fail --silent --show-error --location --retry 2 --output $image https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.vmdk
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo descargar la imagen oficial' }
}
$sumLine = Get-Content (Join-Path $runtime 'SHA256SUMS') | Where-Object { $_ -match ' \*ubuntu-24.04-server-cloudimg-amd64.vmdk$' }
if (!$sumLine -or (Get-FileHash -Algorithm SHA256 -LiteralPath $image).Hash -ne $sumLine.Split(' ')[0]) {
  throw 'La imagen no coincide con el SHA-256 oficial. Descargala de nuevo.'
}
$envValues = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $root '.env')) {
  if ($line -match '^([A-Z_]+)=(.*)$') { $envValues[$matches[1]] = $matches[2].Trim().Trim('"').Trim("'") }
}
foreach ($name in @('POSTGRES_PASSWORD','DB_PASSWORD','MONGO_ROOT_PASSWORD','MONGO_PASSWORD','JWT_SECRET')) {
  if (!$envValues[$name]) { throw "Falta $name en .env" }
}
$key = Join-Path $runtime 'id_ed25519'
if (!(Test-Path -LiteralPath $key)) {
  & ssh-keygen.exe -q -t ed25519 -f $key -N '""' -C 'sirav-virtualbox'
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la clave SSH' }
}
$publicKey = (Get-Content -LiteralPath "$key.pub" -Raw).Trim()
$accessFile = Join-Path $runtime 'access.json'
if (Test-Path -LiteralPath $accessFile) { $access = Get-Content $accessFile -Raw | ConvertFrom-Json }
else {
  $access = @{ user = 'sirav'; consolePassword = (New-Secret); sshKey = $key }
  Write-Utf8 $accessFile ($access | ConvertTo-Json)
}
# Restrict the generated key and access record to the current Windows account.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach ($privateFile in @($key,$accessFile)) {
  & icacls.exe $privateFile '/inheritance:r' '/grant:r' "${identity}:(F)" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo restringir el archivo de acceso' }
}
$definitions = @(
  @{ Name='SIRAV-PostgreSQL'; Hostname='sirav-postgres'; Ip='192.168.56.21'; Mac='080027A32101'; Ssh=2221; Db=5432; Forward=15432; Engine='postgres' },
  @{ Name='SIRAV-MongoDB'; Hostname='sirav-mongodb'; Ip='192.168.56.22'; Mac='080027A32201'; Ssh=2222; Db=27017; Forward=17017; Engine='mongo' }
)
$registered = (& $vbox list vms) -join "`n"
foreach ($vm in $definitions) {
  $seedDir = Join-Path $runtime $vm.Name
  $receipt = Join-Path $seedDir 'created-uuid.txt'
  $exists = $registered -match ('"' + [regex]::Escape($vm.Name) + '"')
  if ($exists) {
    $info = (& $vbox showvminfo $vm.Name --machinereadable) -join "`n"
    if (!(Test-Path $receipt) -or $info -notmatch ('UUID="' + [regex]::Escape((Get-Content $receipt -Raw).Trim()) + '"')) {
      throw "$($vm.Name) ya existe sin comprobante de creacion; no se modifica."
    }
    if ($info -match 'description="SIRAV ') { Write-Host "$($vm.Name) ya esta preparada; no se modifica."; continue }
    if ($info -notmatch 'VMState="poweroff"') { throw 'La VM incompleta debe estar apagada para continuar.' }
  }
  New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
  $files = New-Object Collections.Generic.List[object]
  if ($vm.Engine -eq 'postgres') {
    foreach ($source in Get-ChildItem (Join-Path $root 'database/postgres') -File | Where-Object { $_.Name -match '^(0.*\.sql|init\.sh)$' }) {
      $files.Add(@{ Path="/opt/sirav/schema/$($source.Name)"; Text=[IO.File]::ReadAllText($source.FullName); Mode='0644' })
    }
    $engineEnv = "POSTGRES_USER=sirav_owner`nPOSTGRES_DB=sirav_3fn`nPOSTGRES_PASSWORD=$($envValues.POSTGRES_PASSWORD)`nDB_PASSWORD=$($envValues.DB_PASSWORD)`nTZ=America/Bogota`n"
    $dockerCommand = 'docker run -d --name sirav-postgres --restart unless-stopped --memory 1200m --env-file /opt/sirav/database.env -p 5432:5432 -v sirav_postgres_data:/var/lib/postgresql/data -v /opt/sirav/schema:/schema:ro -v /opt/sirav/schema/init.sh:/docker-entrypoint-initdb.d/01-init.sh:ro postgres:17.6-alpine postgres -c timezone=America/Bogota -c shared_buffers=128MB -c max_connections=50'
  } else {
    $files.Add(@{ Path='/opt/sirav/init.js'; Text=[IO.File]::ReadAllText((Join-Path $root 'database/mongo/init.js')); Mode='0644' })
    $engineEnv = "MONGO_INITDB_ROOT_USERNAME=root`nMONGO_INITDB_ROOT_PASSWORD=$($envValues.MONGO_ROOT_PASSWORD)`nMONGO_PASSWORD=$($envValues.MONGO_PASSWORD)`n"
    $dockerCommand = 'docker run -d --name sirav-mongo --restart unless-stopped --memory 1200m --env-file /opt/sirav/database.env -p 27017:27017 -v sirav_mongo_data:/data/db -v /opt/sirav/init.js:/docker-entrypoint-initdb.d/init.js:ro mongo:8.0.5 --wiredTigerCacheSizeGB 0.25'
  }
  $files.Add(@{ Path='/opt/sirav/database.env'; Text=$engineEnv; Mode='0600' })
  $provision = @'
#!/bin/bash
set -euo pipefail
if [ -f /opt/sirav/provisioned ]; then exit 0; fi
exec > >(tee -a /var/log/sirav-provision.log) 2>&1
getent group docker >/dev/null || groupadd --system docker
systemctl reset-failed containerd.service docker.socket docker.service || true
systemctl start containerd.service docker.socket
systemctl enable --now docker
docker info >/dev/null
if ! swapon --show | grep -q /swapfile; then
  if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
sysctl -w vm.swappiness=10
echo 'vm.swappiness=10' > /etc/sysctl.d/90-sirav.conf
__DOCKER_COMMAND__
touch /opt/sirav/provisioned
'@
  $files.Add(@{ Path='/opt/sirav/provision.sh'; Text=$provision.Replace('__DOCKER_COMMAND__',$dockerCommand); Mode='0700' })
  $cloud = @"
#cloud-config
hostname: $($vm.Hostname)
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
packages: [docker.io]
write_files:
"@
  foreach ($file in $files) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($file.Text.Replace("`r`n","`n")))
    $cloud += "`n  - path: $($file.Path)`n    permissions: '$($file.Mode)'`n    encoding: b64`n    content: $b64"
  }
  $cloud += "`nruncmd:`n  - [bash, /opt/sirav/provision.sh]`n"
  Write-Utf8 (Join-Path $seedDir 'user-data') $cloud
  Write-Utf8 (Join-Path $seedDir 'meta-data') "instance-id: $($vm.Hostname)-v1`nlocal-hostname: $($vm.Hostname)`n"
  $colonMac = ($vm.Mac -replace '(..)(?!$)','$1:').ToLowerInvariant()
  Write-Utf8 (Join-Path $seedDir 'network-config') @"
version: 2
ethernets:
  nat:
    match:
      name: enp0s3
    dhcp4: true
  private:
    match:
      macaddress: '$colonMac'
    set-name: lan0
    dhcp4: false
    addresses: [$($vm.Ip)/24]
"@
  # VISO is VirtualBox's built-in virtual ISO format; cloud-init sees a CIDATA CD.
  $viso = Join-Path $seedDir 'seed.viso'
  $visoText = "--iprt-iso-maker-file-marker=$([guid]::NewGuid())`n--volume-id=CIDATA`n--iso-level=3`n--rock-ridge`n"
  foreach ($seedFile in @('user-data','meta-data','network-config')) {
    $sourcePath = (Join-Path $seedDir $seedFile).Replace('\','/')
    $visoText += '"/' + $seedFile + '=' + $sourcePath + '"' + "`n"
  }
  Write-Utf8 $viso $visoText
  $disk = Join-Path (Join-Path $VmFolder $vm.Name) 'system.vdi'
  if (!$exists) {
    VBox createvm --name $vm.Name --ostype Ubuntu_64 --basefolder $VmFolder --register
    $newInfo = (& $vbox showvminfo $vm.Name --machinereadable) -join "`n"
    if ($newInfo -match '(?m)^UUID="([^"]+)"') { Write-Utf8 $receipt $matches[1] }
    else { throw 'No se pudo registrar el comprobante de creacion' }
  }
  if (!(Test-Path -LiteralPath $disk)) {
    VBox clonemedium disk $image $disk --format VDI
    # Cloud VMDKs have a zero UUID on disk. Deregister the source before reusing it.
    VBox closemedium disk $image
  }
  VBox modifymedium disk $disk --resize 20480
  VBox modifyvm $vm.Name --memory 2048 --cpus 2 --ioapic on --paravirtprovider minimal --hpet on --graphicscontroller vmsvga --vram 16 --audio-enabled off --usb off --boot1 disk --boot2 dvd --boot3 none --boot4 none --nic1 nat --nic2 hostonly --hostonlyadapter2 $HostOnlyAdapter --macaddress2 $vm.Mac --cableconnected1 on --cableconnected2 on
  VBox modifyvm $vm.Name --natpf1 "ssh,tcp,127.0.0.1,$($vm.Ssh),,22" --natpf1 "database,tcp,127.0.0.1,$($vm.Forward),,$($vm.Db)"
  VBox storagectl $vm.Name --name SATA --add sata --controller IntelAhci --portcount 2 --bootable on
  VBox storageattach $vm.Name --storagectl SATA --port 0 --device 0 --type hdd --medium $disk
  VBox storageattach $vm.Name --storagectl SATA --port 1 --device 0 --type dvddrive --medium $viso
  VBox modifyvm $vm.Name --description "SIRAV $($vm.Engine): Ubuntu Server 24.04 LTS, 2048 MB RAM, 2 vCPU, disco dinamico 20 GB. Privada: $($vm.Ip). SSH localhost:$($vm.Ssh); base localhost:$($vm.Forward)."
  Write-Host "Creada $($vm.Name): 2048 MB, IP $($vm.Ip), SSH $($vm.Ssh)."
}
$mongoPassword = [Uri]::EscapeDataString($envValues.MONGO_PASSWORD)
$backendEnv = "DB_URL=jdbc:postgresql://127.0.0.1:15432/sirav_3fn`nDB_USER=sirav_app`nDB_PASSWORD=$($envValues.DB_PASSWORD)`nMONGO_URI=mongodb://sirav_app:${mongoPassword}@127.0.0.1:17017/sirav_3fn?authSource=sirav_3fn`nJWT_SECRET=$($envValues.JWT_SECRET)`nSEED_DEMO=$($envValues.SEED_DEMO)`nDEMO_PASSWORD=$($envValues.DEMO_PASSWORD)`nCORS_ORIGIN=http://localhost:5173,http://127.0.0.1:5173`n"
Write-Utf8 (Join-Path $runtime 'backend.env') $backendEnv
Write-Host 'VM creadas y apagadas. Sus credenciales estan en .runtime/virtualbox (ignorado por Git).'
