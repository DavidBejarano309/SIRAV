param([string]$BackupRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) 'backups'),[switch]$Prune)
. (Join-Path $PSScriptRoot 'backup-common.ps1')
$base=[IO.Path]::GetFullPath($BackupRoot).TrimEnd('\','/')
if(!(Test-Path -LiteralPath $base -PathType Container)){throw 'Backup root does not exist.'}
if((Get-Item -LiteralPath $base).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Backup root must not be a junction or symbolic link.'}
$lock=[IO.File]::Open((Join-Path $base '.backup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
  $sets=@(foreach($dir in Get-ChildItem -LiteralPath $base -Directory){
    if($dir.Name -notmatch '^\d{8}T\d{6}Z-[a-f0-9]{8}$' -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
    try {$m=Test-BackupSet $dir.FullName; [pscustomobject]@{Path=$dir.FullName;Time=[DateTimeOffset]::Parse($m.CompletedUtc).UtcDateTime;Id=$dir.Name}}
    catch {Write-Warning "Preserving invalid/incomplete set $($dir.Name): $_"}
  })
  $sets=@($sets | Sort-Object Time -Descending)
  $keep=@{}
  # Latest backup on each UTC day, ISO week and month; keep all sets younger than 14 days.
  foreach($s in $sets){if($s.Time -ge [DateTime]::UtcNow.AddDays(-14)){$keep[$s.Id]=$true}}
  foreach($spec in @(@{Count=14;Kind='day'},@{Count=8;Kind='week'},@{Count=6;Kind='month'})) {
    $seen=@{}
    foreach($s in $sets) {
      switch($spec.Kind){
        day {$key=$s.Time.ToString('yyyyMMdd')}
        month {$key=$s.Time.ToString('yyyyMM')}
        week {$offset=(([int]$s.Time.DayOfWeek+6)%7);$key=$s.Time.Date.AddDays(-$offset).ToString('yyyyMMdd')}
      }
      if(!$seen.ContainsKey($key) -and $seen.Count -lt $spec.Count){$seen[$key]=$true;$keep[$s.Id]=$true}
    }
  }
  foreach($s in $sets){
    if($keep.ContainsKey($s.Id)){Write-Output "KEEP $($s.Path)";continue}
    # Never prune a set whose subtree contains a junction/link or outside-root path.
    $resolved=(Resolve-Path -LiteralPath $s.Path).ProviderPath
    if((Split-Path -Parent $resolved) -ne $base){throw 'Retention target escaped the backup root.'}
    if(Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}){throw 'Retention refuses backup trees containing links.'}
    if($Prune){Remove-Item -LiteralPath $resolved -Recurse -Force;Write-Output "REMOVED $resolved"}
    else {Write-Output "WOULD REMOVE $resolved"}
  }
} finally {$lock.Dispose()}
