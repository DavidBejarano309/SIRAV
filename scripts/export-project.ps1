param([string]$ArchivePath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!$ArchivePath){$ArchivePath=Join-Path $root ('output/SIRAV-proyecto-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.zip')}
$archive=[IO.Path]::GetFullPath($ArchivePath)
if(Test-Path -LiteralPath $archive){throw 'The ZIP already exists; it was preserved. Choose another path.'}
$excluded=@('.git','.tools','.runtime','node_modules','target','dist','coverage','test-results','playwright-report','__pycache__','backups','output','.idea','.vscode')
$files=New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
$pending=New-Object 'System.Collections.Generic.Stack[string]'
foreach($folder in @('backend','frontend','database','deploy','docs','scripts','.github')){$pending.Push((Join-Path $root $folder))}
while($pending.Count){
  foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
    if($item.LinkType -in @('SymbolicLink','Junction')){continue}
    if($item.PSIsContainer){if($item.Name -notin $excluded){$pending.Push($item.FullName)};continue}
    if(($item.Name -like '.env*' -and $item.Name -ne '.env.example') -or $item.Name -like 'id_ed25519*' -or $item.Extension -in @('.zip','.log','.key','.pem','.vdi','.vmdk','.sav')){continue}
    $files.Add($item)
  }
}
foreach($name in @('README.md','.gitignore','.gitattributes','.env.example','compose.yaml','compose.test.yaml')){$files.Add((Get-Item -LiteralPath (Join-Path $root $name)))}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $archive) | Out-Null
$hashes=@{}
$package=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
try {
  foreach($file in $files | Sort-Object FullName){
    $relative=$file.FullName.Substring($root.Length+1).Replace('\','/')
    $name='SIRAV/'+$relative
    $hashes[$name]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $entry=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($package,$file.FullName,$name,[IO.Compression.CompressionLevel]::Optimal)
    if($file.Extension -eq '.sh'){$entry.ExternalAttributes=33261 -shl 16}else{$entry.ExternalAttributes=33188 -shl 16}
  }
} finally {$package.Dispose()}
$package=[IO.Compression.ZipFile]::OpenRead($archive)
try {
  if($package.Entries.Count -ne $files.Count){throw 'ZIP inventory count mismatch.'}
  foreach($entry in $package.Entries){
    $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
    try {$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}
    finally {$sha.Dispose();$stream.Dispose()}
    if($actual -ne $hashes[$entry.FullName]){throw "ZIP integrity check failed: $($entry.FullName)"}
  }
  foreach($required in @('README.md','.env.example','compose.yaml','docs/POLITICA-RESPALDOS.md','docs/WEB-EN-VIRTUALBOX.md','scripts/backup-vms.ps1','deploy/virtualbox/backup-component.sh','frontend/package-lock.json','backend/pom.xml')){
    if(!$package.GetEntry('SIRAV/'+$required)){throw "ZIP missing required file: $required"}
  }
} finally {$package.Dispose()}
$hash=Get-FileHash -LiteralPath $archive -Algorithm SHA256
[IO.File]::WriteAllText(($archive+'.sha256'),($hash.Hash+'  '+[IO.Path]::GetFileName($archive)+"`n"))
Write-Output "ZIP verified: $archive"
Write-Output "Files: $($files.Count); bytes: $((Get-Item -LiteralPath $archive).Length); SHA256: $($hash.Hash)"
