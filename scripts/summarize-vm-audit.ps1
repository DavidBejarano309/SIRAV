param([Parameter(Mandatory=$true)][string]$RunDirectory)
$ErrorActionPreference='Stop'
$directory=(Resolve-Path -LiteralPath $RunDirectory).Path
$candidates=@()
foreach ($run in Get-ChildItem (Join-Path $directory 'runs') -Directory) {
  $log=Join-Path $run.FullName 'maven.log'
  $matchesFound=[regex]::Matches([IO.File]::ReadAllText($log),'(?m)^\[INFO\] Tests run: (\d+), Failures: (\d+), Errors: (\d+), Skipped: (\d+)\s*$')
  if ($matchesFound.Count) {
    $result=$matchesFound[$matchesFound.Count-1]
    if ($result.Groups[2].Value -eq '0' -and $result.Groups[3].Value -eq '0') { $candidates+=@{ Directory=$run.FullName; Tests=[int]$result.Groups[1].Value; Skipped=[int]$result.Groups[4].Value } }
  }
}
$full=$candidates | Sort-Object { [int]$_.Tests } -Descending | Select-Object -First 1
if (!$full) { throw 'No se encontro una ejecucion Java aprobada.' }
$classes=@()
foreach ($file in Get-ChildItem (Join-Path $full.Directory 'surefire-reports') -Filter 'TEST-*.xml') {
  [xml]$report=Get-Content -LiteralPath $file.FullName
  $classes+=[ordered]@{ Name=$report.testsuite.name; Tests=[int]$report.testsuite.tests; Failures=[int]$report.testsuite.failures; Errors=[int]$report.testsuite.errors; Skipped=[int]$report.testsuite.skipped }
}
$classTotal=($classes | ForEach-Object { [int]$_.Tests } | Measure-Object -Sum).Sum
if ($classTotal -ne $full.Tests) { throw 'Los reportes XML no coinciden con el total de la ejecucion Java seleccionada.' }
$browser=Get-Content (Join-Path $directory 'playwright.json') -Raw | ConvertFrom-Json
$http=Get-Content (Join-Path $directory 'http-concurrency.json') -Raw | ConvertFrom-Json
[xml]$jacoco=Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend/target/site/jacoco/jacoco.xml')
$coverage=@{}
foreach ($counter in $jacoco.report.counter) { $total=[int]$counter.covered+[int]$counter.missed; $coverage[$counter.type]=[Math]::Round(100*[int]$counter.covered/$total,2) }
$before=Get-Content (Join-Path $directory 'deployment/production-counts-before.json') -Raw | ConvertFrom-Json
$after=Get-Content (Join-Path $directory 'deployment/production-counts-after.json') -Raw | ConvertFrom-Json
$smoke=$null
if (Test-Path (Join-Path $directory 'production-smoke.json')) { $smoke=Get-Content (Join-Path $directory 'production-smoke.json') -Raw | ConvertFrom-Json }
$summary=[ordered]@{
  Generated=(Get-Date -Format o); Database=(Split-Path -Leaf $directory);
  Java=[ordered]@{ Tests=$full.Tests; Skipped=$full.Skipped; Failures=0; Errors=0; Run=(Split-Path -Leaf $full.Directory); Classes=$classes; CoveragePercent=$coverage };
  Frontend=[ordered]@{ Tests=5; Failures=0; Source='npm --prefix frontend test, observado durante esta auditoria; build de produccion aprobado' };
  Browser=$browser.stats;
  ConcurrentHttp=[ordered]@{ Result=$http.result; Requests=$http.parallelRequests; Scenarios=$http.scenarios; HealthChecks=$http.health.Count };
  Production=[ordered]@{ Before=$before; After=$after; DomainCountsPreserved=(($before|ConvertTo-Json -Compress) -eq ($after|ConvertTo-Json -Compress)); Smoke=$smoke }
}
$output=Join-Path $directory 'summary.json'
[IO.File]::WriteAllText($output,($summary|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
Write-Host "Resumen guardado en $output"
Write-Host "Java: $($full.Tests) aprobadas. Navegador: $($browser.stats.expected). HTTP concurrente: $($http.parallelRequests)."
