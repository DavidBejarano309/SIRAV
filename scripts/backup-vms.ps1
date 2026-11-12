param(
  [string]$BackupRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'backups'),
  [string]$MirrorDirectory
)
. (Join-Path $PSScriptRoot 'backup-common.ps1')
$id=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$destination=Join-Path ([IO.Path]::GetFullPath($BackupRoot)) $id
$lock=$null; $pauseRequested=$false; $created=@(); $success=$false
Push-Location $script:ProjectRoot
try {
  New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
  Protect-BackupDirectory ([IO.Path]::GetFullPath($BackupRoot))
  $lock=[IO.File]::Open((Join-Path $BackupRoot '.backup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  # All preflight checks finish before pausing the API or creating a backup set.
  Invoke-BackupRemote 2221 check-pg $id
  Invoke-BackupRemote 2222 check-mongo $id
  Invoke-BackupRemote 2223 check-web $id
  New-Item -ItemType Directory -Path $destination | Out-Null
  $started=(Get-Date).ToUniversalTime()
  $pauseRequested=$true
  Write-Host 'Pausing the API while PostgreSQL, MongoDB and images are copied.'
  Invoke-BackupRemote 2223 pause $id
  foreach($item in @(@{Port=2221;Mode='pg';Files=@('postgres.dump','postgres-roles.sql','postgres-counts.tsv')},@{Port=2222;Mode='mongo';Files=@('mongodb.archive.gz','mongodb-counts.json')},@{Port=2223;Mode='evidence';Files=@('evidencias.tar.gz')})) {
    $created+= $item.Port
    Invoke-BackupRemote $item.Port $item.Mode $id
    foreach($file in $item.Files){Copy-BackupRemote $item.Port $id $file $destination}
  }
  Invoke-BackupRemote 2223 still-paused $id
  if(((Get-Date).ToUniversalTime()-$started).TotalMinutes -ge 29){throw 'Maintenance window exceeded; set is not certified complete.'}
  $files=@(Get-ChildItem -LiteralPath $destination -File | Sort-Object Name | ForEach-Object {@{Name=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
  $manifest=@{Format='sirav-vm-backup-v1';Status='complete';Database='sirav_3fn';Id=$id;StartedUtc=$started.ToString('o');CompletedUtc=(Get-Date).ToUniversalTime().ToString('o');Consistency='API stopped; no other database writers permitted';PostgresMajor=17;MongoMajor=8;Files=$files;RestoreTest='not-yet-run'}
  [IO.File]::WriteAllText((Join-Path $destination 'manifest.json'),($manifest | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
  Test-BackupSet $destination | Out-Null
  $success=$true
} finally {
  if($pauseRequested){
    try {Invoke-BackupRemote 2223 resume $id; Write-Host 'API restart requested; cold startup can take about 15 minutes.'}
    catch {Write-Warning "API restart request failed. A 30-minute watchdog is armed. Run: sudo systemctl start sirav-api.service. $_"; $success=$false}
  }
  foreach($port in $created){try {Invoke-BackupRemote $port cleanup $id} catch {Write-Warning "Temporary backup files remain on port $port. $_"}}
  if($lock){$lock.Dispose()}
  Pop-Location
}
if(!$success){throw 'Backup did not complete successfully; inspect the output and API state.'}
if($MirrorDirectory){
  $mirror=Join-Path ([IO.Path]::GetFullPath($MirrorDirectory)) $id
  if(Test-Path -LiteralPath $mirror){throw 'Mirror destination already exists; it was preserved.'}
  New-Item -ItemType Directory -Force -Path $mirror | Out-Null
  foreach($file in Get-ChildItem -LiteralPath $destination -File){Copy-Item -LiteralPath $file.FullName -Destination $mirror}
  Test-BackupSet $mirror | Out-Null
  Write-Host "Mirror verified: $mirror"
}
Write-Host "Backup complete and SHA-256 verified: $destination"
Write-Host 'Run test-backup-vms.ps1 for an isolated restoration drill. No retention deletion is performed.'
