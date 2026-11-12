# Shared by the VirtualBox backup and isolated restore drill. Windows PowerShell 5.1+.
$ErrorActionPreference='Stop'
$script:ProjectRoot=Split-Path -Parent $PSScriptRoot
function Invoke-BackupRemote([int]$Port,[string]$Mode,[string]$Id) {
  $source=[IO.File]::ReadAllText((Join-Path $script:ProjectRoot 'deploy/virtualbox/backup-component.sh')).Replace("`r`n","`n")
  $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source))
  & ssh.exe -i .runtime/virtualbox/id_ed25519 -p $Port -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.runtime/virtualbox/known_hosts sirav@127.0.0.1 "echo $encoded | base64 -d | sudo bash -s -- $Mode $Id"
  if($LASTEXITCODE -ne 0){throw "Backup operation '$Mode' failed on SSH port $Port (exit $LASTEXITCODE)."}
}
function Copy-BackupRemote([int]$Port,[string]$Id,[string]$File,[string]$Directory,[switch]$Upload) {
  $remote="sirav@127.0.0.1:/home/sirav/sirav-backup-$Id/$File"
  $local=Join-Path $Directory $File
  $copyArgs=@('-q','-i','.runtime/virtualbox/id_ed25519','-P',"$Port",'-o','BatchMode=yes','-o','ConnectTimeout=20','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile=.runtime/virtualbox/known_hosts')
  if($Upload){ & scp.exe @copyArgs $local $remote } else { & scp.exe @copyArgs $remote $local }
  if($LASTEXITCODE -ne 0){throw "Could not transfer $File on SSH port $Port."}
}
function Protect-BackupDirectory([string]$Directory) {
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
  & icacls.exe $Directory '/inheritance:r' '/grant:r' "${identity}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'Could not restrict access to the backup directory.'}
}
function Test-BackupSet([string]$Directory) {
  $manifestPath=Join-Path $Directory 'manifest.json'
  $m=Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
  if($m.Format -ne 'sirav-vm-backup-v1' -or $m.Status -ne 'complete' -or $m.Database -ne 'sirav_3fn'){throw 'Invalid or incomplete backup manifest.'}
  $expected=@('postgres.dump','postgres-roles.sql','postgres-counts.tsv','mongodb.archive.gz','mongodb-counts.json','evidencias.tar.gz')
  if(@($m.Files).Count -ne $expected.Count){throw 'Incomplete file inventory.'}
  foreach($name in $expected) {
    $entry=@($m.Files | Where-Object {$_.Name -ceq $name})
    if($entry.Count -ne 1){throw "Invalid inventory entry: $name"}
    $path=Join-Path $Directory $name
    $f=Get-Item -LiteralPath $path
    if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.PSIsContainer){throw "Unsupported backup file: $name"}
    if($f.Length -le 0 -or $f.Length -ne $entry[0].Bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry[0].SHA256){throw "Backup integrity check failed: $name"}
  }
  return $m
}
