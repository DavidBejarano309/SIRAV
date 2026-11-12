param([string]$Java='C:\Program Files\Java\jdk-23\bin\java.exe')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Join-Path $root '.runtime/virtualbox/backend.env'
if (!(Test-Path -LiteralPath $config)) { throw 'Ejecuta primero scripts/create-database-vms.ps1' }
foreach ($line in Get-Content -LiteralPath $config) {
  if ($line -match '^([A-Z_]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1],$matches[2],'Process') }
}
& (Join-Path $PSScriptRoot 'start-local-api.ps1') -Java $Java
