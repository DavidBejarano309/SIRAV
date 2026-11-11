param([string]$Maven='mvn',[int]$PostgresPort=55432,[int]$MongoPort=57017)
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
 # Algunos lanzadores Windows virtualizan AF_UNIX. Un directorio inexistente
 # hace que PipeImpl use su alternativa TCP documentada en el código del JDK.
 # Es solo una adaptación del entorno de pruebas; no cambia la aplicación.
 if($IsWindows) { $env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir="'+(Join-Path $PSScriptRoot '../.runtime/unix-sockets-disabled')+'"' }
 & (Join-Path $PSScriptRoot 'init-local-db.ps1') -Database 'sirav_3fn_test' -Port $PostgresPort
 $env:DB_URL="jdbc:postgresql://127.0.0.1:$PostgresPort/sirav_3fn_test"
 $env:DB_USER='sirav_app'
 $env:DB_PASSWORD='local-app-change-me'
 $env:MONGO_URI="mongodb://127.0.0.1:$MongoPort/sirav_3fn_test"
 $env:JWT_SECRET='local-test-key-with-more-than-thirty-two-characters'
 $env:SEED_DEMO='true'
 $env:DEMO_PASSWORD='SiravDemo2026!'
 $env:SIRAV_INTEGRATION='true'
 & $Maven -B -f backend/pom.xml clean verify
 if($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas del backend' }
 Push-Location frontend
 try { npm.cmd test; if($LASTEXITCODE -ne 0){throw 'Fallaron las pruebas frontend'}; npm.cmd run build; if($LASTEXITCODE -ne 0){throw 'Falló el build frontend'} } finally { Pop-Location }
} finally { Pop-Location }
