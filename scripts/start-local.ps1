param(
    [string]$Postgres = 'C:\Program Files\PostgreSQL\18\bin\postgres.exe',
    [string]$Java = 'C:\Program Files\Java\jdk-23\bin\java.exe',
    [string]$Mongo = '',
    [switch]$DatabasesOnly,
    [switch]$RestartApi
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root '.runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null

function Test-LocalPort([int]$Port) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $connection = $client.ConnectAsync('127.0.0.1', $Port)
        if (!$connection.Wait(800)) { return $false }
        return $client.Connected
    } catch { return $false }
    finally { $client.Dispose() }
}

function Wait-LocalPort([int]$Port, [string]$Service) {
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if (Test-LocalPort $Port) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "$Service no inició en el puerto $Port. Revisa los logs en $runtime"
}

function Start-HiddenService([string]$File, [string[]]$Arguments, [string]$Directory, [string]$Name) {
    if (!(Test-Path -LiteralPath $File)) { throw "No se encontró $File" }
    $process = Start-Process -FilePath $File -ArgumentList $Arguments -WorkingDirectory $Directory `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $runtime "$Name-stdout.log") `
        -RedirectStandardError (Join-Path $runtime "$Name-stderr.log")
    Write-Host "$Name iniciado (PID $($process.Id))"
}

if (!(Test-Path -LiteralPath (Join-Path $runtime 'pgdata/PG_VERSION'))) {
    throw 'Falta inicializar PostgreSQL local. Consulta README.md o usa Docker Compose.'
}

if (!(Test-LocalPort 55432)) {
    Start-HiddenService $Postgres @('-D', ('"' + (Join-Path $runtime 'pgdata') + '"'), '-p', '55432', '-h', '127.0.0.1', '-c', 'shared_buffers=32MB', '-c', 'max_connections=30') $root 'postgres'
}
Wait-LocalPort 55432 'PostgreSQL'
& (Join-Path $PSScriptRoot 'init-local-db.ps1') -Psql (Join-Path (Split-Path -Parent $Postgres) 'psql.exe')

if (!(Test-LocalPort 57017)) {
    if (!$Mongo) {
        $bundled = Get-ChildItem -LiteralPath (Join-Path $root '.tools/mongodb') -Recurse -Filter mongod.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bundled) { $Mongo = $bundled.FullName }
        else {
            $installed = Get-Command mongod.exe -ErrorAction SilentlyContinue
            if ($installed) { $Mongo = $installed.Source }
            else { throw 'No se encontró MongoDB. Instálalo o usa Docker Compose.' }
        }
    }
    Start-HiddenService $Mongo @('--dbpath', ('"' + (Join-Path $runtime 'mongodata') + '"'), '--port', '57017', '--bind_ip', '127.0.0.1', '--logpath', ('"' + (Join-Path $runtime 'mongodb.log') + '"'), '--logappend') $root 'mongo'
}
Wait-LocalPort 57017 'MongoDB'
if ($DatabasesOnly) { Write-Host 'Bases locales disponibles; sirav_3fn inicializada.'; return }

if ($RestartApi -and (Test-LocalPort 8080)) {
    $connection = Get-NetTCPConnection -State Listen -LocalPort 8080 | Select-Object -First 1
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($connection.OwningProcess)"
    $expectedJar = Join-Path $runtime 'sirav-api.jar'
    if (!$process.CommandLine -or !$process.CommandLine.Contains($expectedJar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'El puerto 8080 pertenece a otro proceso. No se detiene.'
    }
    Stop-Process -Id $connection.OwningProcess
    for ($attempt=0; $attempt -lt 40 -and (Test-LocalPort 8080); $attempt++) { Start-Sleep -Milliseconds 250 }
}
if (!(Test-LocalPort 8080)) {
    $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    Start-HiddenService $pwsh @('-NoProfile', '-File', ('"' + (Join-Path $PSScriptRoot 'start-local-api.ps1') + '"'), '-Java', ('"' + $Java + '"')) $root 'api'
}
Wait-LocalPort 8080 'API'

if (!(Test-LocalPort 5173)) {
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    Start-HiddenService $node @(('"' + (Join-Path $root 'frontend/node_modules/vite/bin/vite.js') + '"'), '--host', '127.0.0.1', '--port', '5173', '--strictPort') (Join-Path $root 'frontend') 'frontend'
}
Wait-LocalPort 5173 'React'

$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
        $health = Invoke-RestMethod 'http://localhost:8080/actuator/health' -TimeoutSec 3
        $web = Invoke-WebRequest 'http://localhost:5173' -TimeoutSec 3
        if ($health.status -eq 'UP' -and $web.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Milliseconds 500 }
}
if (!$ready) { throw 'Los procesos iniciaron, pero la verificación de salud no pasó. Revisa .runtime/*-stderr.log.' }
Write-Host 'SIRAV listo: http://localhost:5173'
Write-Host 'API y conexiones a PostgreSQL/MongoDB: UP'
