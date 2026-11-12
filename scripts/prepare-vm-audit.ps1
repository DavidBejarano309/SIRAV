param([string]$Database=('sirav_audit_'+(Get-Date -Format 'yyyyMMddHHmmss')),[switch]$Resume)
$ErrorActionPreference='Stop'
if ($Database -notmatch '^sirav_audit_[0-9]{14}$') { throw 'Se requiere un nombre nuevo sirav_audit_FECHA.' }
$root=Split-Path -Parent $PSScriptRoot
$run=Join-Path $root ('.runtime/audit/'+$Database)
New-Item -ItemType Directory -Force -Path $run | Out-Null
$values=@{}
foreach ($line in Get-Content -LiteralPath (Join-Path $root '.env')) {
  if ($line -match '^([A-Z_]+)=(.*)$') { $values[$matches[1]]=$matches[2].Trim().Trim('"').Trim("'") }
}
$psql='C:\Program Files\PostgreSQL\18\bin\psql.exe'
$env:PGPASSWORD=$values.POSTGRES_PASSWORD
$env:PGCONNECT_TIMEOUT='15'
try {
  $exists=& $psql -h 127.0.0.1 -p 15432 -U sirav_owner -d postgres -w -tAc "SELECT 1 FROM pg_database WHERE datname='$Database'"
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar PostgreSQL' }
  if ($exists -and (!$Resume -or !(Test-Path (Join-Path $run 'created.txt')))) { throw 'La base de auditoria ya existe; se conserva sin cambios.' }
  if (!$exists) {
    & $psql -h 127.0.0.1 -p 15432 -U sirav_owner -d postgres -w -v ON_ERROR_STOP=1 -c "CREATE DATABASE $Database OWNER sirav_owner"
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la base aislada' }
    [IO.File]::WriteAllText((Join-Path $run 'created.txt'),$Database)
  }
  $initialized=& $psql -h 127.0.0.1 -p 15432 -U sirav_owner -d $Database -w -tAc "SELECT to_regclass('public.usuario') IS NOT NULL"
  $sqlArgs=@('-h','127.0.0.1','-p','15432','-U','sirav_owner','-d',$Database,'-w','-v','ON_ERROR_STOP=1','--single-transaction')
  foreach ($file in Get-ChildItem (Join-Path $root 'database/postgres') -Filter '0*.sql' | Sort-Object Name) { $sqlArgs+=@('-f',$file.FullName) }
  if ($initialized -ne 't') {
    & $psql @sqlArgs | Out-File (Join-Path $run 'schema.log') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la carga SQL aislada; se revirtio la transaccion' }
  }
} finally { Remove-Item Env:PGPASSWORD,Env:PGCONNECT_TIMEOUT -ErrorAction SilentlyContinue }
$mongoInit=[IO.File]::ReadAllText((Join-Path $root 'database/mongo/init.js')).Replace("'sirav_3fn'","'$Database'")
$mongoEncoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($mongoInit.Replace("`r`n","`n")))
$remote=@'
set -e
docker exec sirav-mongo sh -c 'echo __ENCODED__ | base64 -d > /tmp/sirav-audit-init.js; mongosh --quiet --username root --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin /tmp/sirav-audit-init.js'
'@
$remote=$remote.Replace('__ENCODED__',$mongoEncoded)
$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote.Replace("`r`n","`n")))
Push-Location $root
try {
  & ssh.exe -i .runtime/virtualbox/id_ed25519 -p 2222 -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.runtime/virtualbox/known_hosts sirav@127.0.0.1 "echo $encoded | base64 -d | sudo bash" | Out-File (Join-Path $run 'mongo-init.log') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'Fallo la inicializacion Mongo aislada' }
} finally { Pop-Location }
$settings=@{
  Database=$Database; RunDirectory=$run;
  DB_URL="jdbc:postgresql://127.0.0.1:15432/$Database";
  DB_USER='sirav_app'; DB_PASSWORD=$values.DB_PASSWORD;
  MONGO_URI=('mongodb://sirav_app:'+([Uri]::EscapeDataString($values.MONGO_PASSWORD))+"@127.0.0.1:17017/${Database}?authSource=$Database");
  JWT_SECRET=('audit-only-key-'+[guid]::NewGuid().ToString('N'));
  SEED_DEMO='true'; DEMO_PASSWORD='AuditDemo2026!';
  SIRAV_INTEGRATION='true'; SIRAV_TEST_EVIDENCE_DIR=(Join-Path $run 'evidencias')
}
$config=Join-Path $run 'settings.json'
[IO.File]::WriteAllText($config,($settings | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $config '/inheritance:r' '/grant:r' "${identity}:(F)" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'No se pudo proteger la configuracion de auditoria' }
Write-Host "Preparadas bases aisladas: $Database en PostgreSQL y MongoDB."
Write-Host "Configuracion: $config"
