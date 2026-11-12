$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$envFile=Join-Path $root '.env'
if(Test-Path -LiteralPath $envFile) { Write-Host '.env ya existe. Se conserva la configuración.'; exit 0 }
function New-Secret { [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLowerInvariant() }
$settings=@(
 "POSTGRES_PASSWORD=$(New-Secret)",
 "DB_PASSWORD=$(New-Secret)",
 "MONGO_ROOT_PASSWORD=$(New-Secret)",
 "MONGO_PASSWORD=$(New-Secret)",
 "JWT_SECRET=$(New-Secret)",
 'DEMO_PASSWORD=SiravDemo2026!',
 'SEED_DEMO=true'
)
[IO.File]::WriteAllLines($envFile,$settings,[Text.UTF8Encoding]::new($false))
Write-Host 'Configuración creada. Las credenciales técnicas son aleatorias; revisa .env antes del despliegue.'
