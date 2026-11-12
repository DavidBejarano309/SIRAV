param([Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$directory=[IO.Path]::GetFullPath($EvidenceDirectory)
$auditRoot=[IO.Path]::GetFullPath((Join-Path $root '.runtime/audit'))+[IO.Path]::DirectorySeparatorChar
if (!$directory.StartsWith($auditRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Las evidencias deben guardarse en .runtime/audit.' }
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$ownerLine=Get-Content -LiteralPath (Join-Path $root '.env') | Where-Object { $_ -match '^POSTGRES_PASSWORD=' } | Select-Object -First 1
$env:PGPASSWORD=$ownerLine.Substring('POSTGRES_PASSWORD='.Length).Trim().Trim('"').Trim("'")
$env:PGCONNECT_TIMEOUT='15'
$psql='C:\Program Files\PostgreSQL\18\bin\psql.exe'
$dump='C:\Program Files\PostgreSQL\18\bin\pg_dump.exe'
$counts="SELECT json_build_object('usuarios',(SELECT count(*) FROM usuario),'clientes',(SELECT count(*) FROM cliente),'vehiculos',(SELECT count(*) FROM vehiculo),'reservas',(SELECT count(*) FROM reserva),'alquileres',(SELECT count(*) FROM alquiler),'pagos',(SELECT count(*) FROM pago))"
try {
  & $dump -h 127.0.0.1 -p 15432 -U sirav_owner -d sirav_3fn -w --schema-only --file (Join-Path $directory 'production-schema-before.sql')
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo respaldar el esquema; no se aplica la migracion.' }
  & $psql -h 127.0.0.1 -p 15432 -U sirav_owner -d sirav_3fn -w -tAc $counts | Out-File (Join-Path $directory 'production-counts-before.json') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo registrar el estado inicial' }
  & $psql -h 127.0.0.1 -p 15432 -U sirav_owner -d sirav_3fn -w -v ON_ERROR_STOP=1 --single-transaction -f (Join-Path $root 'database/postgres/07-concurrency-validation.sql')
  if ($LASTEXITCODE -ne 0) { throw 'La migracion se revirtio por un error' }
  & $psql -h 127.0.0.1 -p 15432 -U sirav_owner -d sirav_3fn -w -tAc $counts | Out-File (Join-Path $directory 'production-counts-after.json') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo registrar el estado final' }
} finally { Remove-Item Env:PGPASSWORD,Env:PGCONNECT_TIMEOUT -ErrorAction SilentlyContinue }
Push-Location $root
try {
  & scp.exe -i .runtime/virtualbox/id_ed25519 -P 2221 -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.runtime/virtualbox/known_hosts database/postgres/07-concurrency-validation.sql sirav@127.0.0.1:07-concurrency-validation.sql
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo sincronizar la migracion en la VM' }
  & ssh.exe -i .runtime/virtualbox/id_ed25519 -p 2221 -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.runtime/virtualbox/known_hosts sirav@127.0.0.1 'sudo install -m 0644 /home/sirav/07-concurrency-validation.sql /opt/sirav/schema/07-concurrency-validation.sql'
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo conservar la migracion en el inicializador de la VM' }
} finally { Pop-Location }
Write-Host 'Migracion SQL aplicada. Esquema anterior y conteos guardados como evidencia.'
