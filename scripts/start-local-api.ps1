param([string]$Java='java',[int]$PostgresPort=55432,[int]$MongoPort=57017)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$jar=Join-Path $root 'backend/target/sirav-api-1.0.0.jar'
if(!(Test-Path -LiteralPath $jar)) { throw 'Compila primero: mvn -f backend/pom.xml verify' }
# Valores exclusivos del entorno local de pruebas. En producción usar Compose y .env.
if(!$env:DB_URL) { $env:DB_URL="jdbc:postgresql://127.0.0.1:$PostgresPort/sirav_3fn" }
if(!$env:DB_USER) { $env:DB_USER='sirav_app' }
if(!$env:DB_PASSWORD) { $env:DB_PASSWORD='local-app-change-me' }
if(!$env:MONGO_URI) { $env:MONGO_URI="mongodb://127.0.0.1:$MongoPort/sirav_3fn" }
if(!$env:JWT_SECRET) { $env:JWT_SECRET='local-test-key-with-more-than-thirty-two-characters' }
if(!$env:SEED_DEMO) { $env:SEED_DEMO='true' }
if(!$env:DEMO_PASSWORD) { $env:DEMO_PASSWORD='SiravDemo2026!' }
$runtime=Join-Path $root '.runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$runJar=Join-Path $runtime 'sirav-api.jar'
Copy-Item -LiteralPath $jar -Destination $runJar -Force
$jvmOptions=@()
if($IsWindows) { $jvmOptions+=('-Djdk.net.unixdomain.tmpdir='+(Join-Path $root '.runtime/unix-sockets-disabled')) }
& $Java @jvmOptions -jar $runJar
