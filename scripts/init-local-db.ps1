param(
    [string]$Database = 'sirav_3fn',
    [int]$Port = 55432,
    [string]$Psql = 'C:\Program Files\PostgreSQL\18\bin\psql.exe'
)
$ErrorActionPreference = 'Stop'
if ($Database -notmatch '^sirav_3fn(_test)?$') { throw 'Solo se permite inicializar sirav_3fn o sirav_3fn_test.' }
$root = Split-Path -Parent $PSScriptRoot
$ready = Join-Path (Split-Path -Parent $Psql) 'pg_isready.exe'
for ($attempt=0; $attempt -lt 60; $attempt++) {
    & $ready -h 127.0.0.1 -p $Port -U postgres -d postgres *> $null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Milliseconds 500
}
if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL todavía no acepta conexiones.' }
function Invoke-Sql([string]$Db, [string]$Sql) {
    $result = & $Psql -h 127.0.0.1 -p $Port -U postgres -d $Db -v ON_ERROR_STOP=1 -tAc $Sql
    if ($LASTEXITCODE -ne 0) { throw 'Falló la inicialización de PostgreSQL.' }
    return $result
}
$exists = Invoke-Sql 'postgres' "SELECT 1 FROM pg_database WHERE datname='$Database'"
if (!$exists) { $null = Invoke-Sql 'postgres' "CREATE DATABASE $Database" }
$role = Invoke-Sql 'postgres' "SELECT 1 FROM pg_roles WHERE rolname='sirav_app'"
if (!$role) { $null = Invoke-Sql 'postgres' "CREATE ROLE sirav_app LOGIN PASSWORD 'local-app-change-me'" }
$initialized = Invoke-Sql $Database "SELECT to_regclass('public.usuario') IS NOT NULL"
if ($initialized -eq 't') {
    $view = Invoke-Sql $Database "SELECT to_regclass('public.v_cliente_contacto') IS NOT NULL"
    if ($view -ne 't') { throw 'La base existente no tiene el esquema revisado. Se conserva sin cambios.' }
    $updated = Invoke-Sql $Database "SELECT to_regprocedure('public.sp_cargar_historial_demo()') IS NOT NULL"
    if ($updated -ne 't') {
        & $Psql -h 127.0.0.1 -p $Port -U postgres -d $Database -v ON_ERROR_STOP=1 --single-transaction -f (Join-Path $root 'database/postgres/06-supuestos.sql')
        if ($LASTEXITCODE -ne 0) { throw 'Se revirtió la ampliación de supuestos.' }
    }
    & $Psql -h 127.0.0.1 -p $Port -U postgres -d $Database -v ON_ERROR_STOP=1 --single-transaction -f (Join-Path $root 'database/postgres/07-concurrency-validation.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Se revirtieron las correcciones de concurrencia.' }
    Write-Host "$Database ya está inicializada y actualizada."
    return
}
$arguments = @('-h','127.0.0.1','-p',"$Port",'-U','postgres','-d',$Database,'-v','ON_ERROR_STOP=1','--single-transaction')
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'database/postgres') -Filter '0*.sql' | Sort-Object Name) {
    $arguments += @('-f',$file.FullName)
}
& $Psql @arguments
if ($LASTEXITCODE -ne 0) { throw 'El esquema se revirtió por un error. La base anterior no se modifica.' }
Write-Host "Base nueva $Database creada con el esquema 3FN."
