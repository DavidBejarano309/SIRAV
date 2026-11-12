param([Parameter(Mandatory=$true)][string]$BackupDirectory,[switch]$IntegrityOnly)
. (Join-Path $PSScriptRoot 'backup-common.ps1')
$directory=[IO.Path]::GetFullPath($BackupDirectory)
$manifest=Test-BackupSet $directory
if($IntegrityOnly){Write-Host 'PASS: complete manifest, six files, sizes and SHA-256 checksums.'; return}
$id=(Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$target='sirav_restore_'+($id -replace '[-TZ]','')
$results=Join-Path $directory ('restore-drill-'+$id)
New-Item -ItemType Directory -Path $results | Out-Null
$started=(Get-Date).ToUniversalTime()
Push-Location $script:ProjectRoot
try {
  Invoke-BackupRemote 2221 check-pg $id
  Invoke-BackupRemote 2222 check-mongo $id
  foreach($item in @(@{Port=2221;File='postgres.dump';Mode='restore-pg';Counts='postgres-counts.tsv'},@{Port=2222;File='mongodb.archive.gz';Mode='restore-mongo';Counts='mongodb-counts.json'},@{Port=2223;File='evidencias.tar.gz';Mode='restore-evidence';Counts=$null})) {
    Invoke-BackupRemote $item.Port restore-prepare $id
    Copy-BackupRemote $item.Port $id $item.File $directory -Upload
    Invoke-BackupRemote $item.Port $item.Mode $id
    if($item.Counts){Copy-BackupRemote $item.Port $id $item.Counts $results}
  }
  $source=(Get-Content -LiteralPath (Join-Path $directory 'postgres-counts.tsv') -Raw).Trim()
  $restored=(Get-Content -LiteralPath (Join-Path $results 'postgres-counts.tsv') -Raw).Trim()
  if($source -cne $restored){throw 'Restored PostgreSQL table counts do not match the backup.'}
  $sourceMongo=Get-Content -LiteralPath (Join-Path $directory 'mongodb-counts.json') -Raw | ConvertFrom-Json
  $restoredMongo=Get-Content -LiteralPath (Join-Path $results 'mongodb-counts.json') -Raw | ConvertFrom-Json
  if(($sourceMongo | ConvertTo-Json -Depth 8 -Compress) -cne ($restoredMongo | ConvertTo-Json -Depth 8 -Compress)){throw 'Restored MongoDB document or index counts do not match the backup.'}
  $result=@{Status='PASS';SourceBackup=$manifest.Id;TargetDatabase=$target;CompletedUtc=(Get-Date).ToUniversalTime().ToString('o');ElapsedSeconds=[math]::Round(((Get-Date).ToUniversalTime()-$started).TotalSeconds,1);Checks=@('six file hashes','PostgreSQL full restore with constraints and grants','all public table counts','MongoDB full restore with collection metadata','all collection document and index counts','evidence archive decompressed and extracted');ProductionChanged=$false}
  [IO.File]::WriteAllText((Join-Path $results 'result.json'),($result | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
  Write-Host "PASS: restored isolated databases $target. Evidence: $results"
  Write-Host "Drill databases and /home/sirav/sirav-backup-$id were retained; production was not changed."
} catch {
  [IO.File]::WriteAllText((Join-Path $results 'failure.txt'),("Restore drill failed: $_"))
  throw
} finally {Pop-Location}
