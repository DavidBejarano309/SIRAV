param([Parameter(Mandatory=$true)][string]$Settings,[string]$Url='http://192.168.1.18:8089')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json
if ($config.Database -notmatch '^sirav_audit_[0-9]{14}$' -or ([uri]$Url).Port -ne 8089) { throw 'Solo se permite la instancia aislada de auditoria.' }
$env:SIRAV_WEB_URL=$Url
$env:DEMO_PASSWORD=$config.DEMO_PASSWORD
$env:SIRAV_EVIDENCE_DIR=Join-Path $config.RunDirectory 'browser-evidence'
$env:PLAYWRIGHT_JSON_OUTPUT_FILE=Join-Path $config.RunDirectory 'playwright.json'
$env:SIRAV_EXPECT_TIMEOUT_MS='20000'
$env:PLAYWRIGHT_CHANNEL='msedge'
Push-Location $root
try {
  $previousPreference=$ErrorActionPreference
  $ErrorActionPreference='Continue'
  & 'C:\Program Files\nodejs\node.exe' frontend/node_modules/@playwright/test/cli.js test --config frontend/playwright.config.js --timeout=90000 --reporter=list,json --output (Join-Path $config.RunDirectory 'playwright-artifacts') 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath (Join-Path $config.RunDirectory 'playwright.log')
  $testExit=$LASTEXITCODE
  $ErrorActionPreference=$previousPreference
  if ($testExit -ne 0) { throw 'Hubo fallos en los flujos del navegador; revisa playwright.json y las capturas.' }
} finally { Pop-Location }
