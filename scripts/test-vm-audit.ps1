param([Parameter(Mandatory=$true)][string]$Settings,[string]$Maven='',[string]$Tests='',[switch]$Clean)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json
if ($config.Database -notmatch '^sirav_audit_[0-9]{14}$' -or $config.DB_URL -notmatch ('/'+$config.Database+'$') -or $config.MONGO_URI -notmatch ('/'+$config.Database+'\?authSource='+$config.Database+'$')) { throw 'Las conexiones deben apuntar a las bases aisladas de auditoria.' }
foreach ($name in @('DB_URL','DB_USER','DB_PASSWORD','MONGO_URI','JWT_SECRET','SEED_DEMO','DEMO_PASSWORD','SIRAV_INTEGRATION','SIRAV_TEST_EVIDENCE_DIR')) {
  [Environment]::SetEnvironmentVariable($name,$config.$name,'Process')
}
$env:JAVA_HOME='C:\Program Files\Java\jdk-23'
$env:SIRAV_AUDIT='true'
$ownerLine=Get-Content -LiteralPath (Join-Path $root '.env') | Where-Object { $_ -match '^POSTGRES_PASSWORD=' } | Select-Object -First 1
$env:SIRAV_AUDIT_OWNER_PASSWORD=$ownerLine.Substring('POSTGRES_PASSWORD='.Length).Trim().Trim('"').Trim("'")
$env:JAVA_TOOL_OPTIONS='-Duser.timezone=America/Bogota -Djdk.net.unixdomain.tmpdir="'+(Join-Path $config.RunDirectory 'disabled-unix-sockets')+'"'
if (!$Maven) {
  $Maven=Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.m2/wrapper/dists') -Recurse -Filter mvn.cmd | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (!$Maven) { throw 'No se encontro Maven; pasa -Maven con la ruta al ejecutable.' }
$mavenArgs=@('-B','-f',(Join-Path $root 'backend/pom.xml'))
if ($Tests) { $mavenArgs+="-Dtest=$Tests" }
if ($Clean) { $mavenArgs+='clean' }
$mavenArgs+='verify'
$execution=Join-Path $config.RunDirectory ('runs/'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $execution | Out-Null
$runStarted=Get-Date
Push-Location $root
try {
  $previousPreference=$ErrorActionPreference
  $ErrorActionPreference='Continue'
  & $Maven @mavenArgs 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath (Join-Path $execution 'maven.log')
  $mavenExit=$LASTEXITCODE
  $ErrorActionPreference=$previousPreference
  $destination=Join-Path $execution 'surefire-reports'
  New-Item -ItemType Directory -Force -Path $destination | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $root 'backend/target/surefire-reports') -File | Where-Object { $_.LastWriteTime -ge $runStarted } | Copy-Item -Destination $destination -Force
  if ($mavenExit -ne 0) { throw 'La auditoria Java tuvo fallos; revisa surefire-reports y maven.log.' }
} finally { Pop-Location }
