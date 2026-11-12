param([string]$Api='http://localhost:8080',[string]$Email='admin@sirav.local',[string]$Password=$env:DEMO_PASSWORD)
$ErrorActionPreference='Stop'
if(!$Password){throw 'Configura DEMO_PASSWORD para una cuenta de demostración'}
$login=Invoke-RestMethod "$Api/api/auth/login" -Method Post -ContentType 'application/json' -Body (@{email=$Email;password=$Password}|ConvertTo-Json)
$headers=@{Authorization="Bearer $($login.token)"}
$today=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'SA Pacific Standard Time').ToString('yyyy-MM-dd')
$from=([DateTime]::Parse($today)).AddDays(-30).ToString('yyyy-MM-dd')
$to=([DateTime]::Parse($today)).AddDays(1).ToString('yyyy-MM-dd')
$results=@("Fecha: $today",'Entorno local Windows; HTTP completo, no medición de VM ni benchmark de carga.')
foreach($report in @('occupancy','revenue','ranking','clients','late','availability','mongo')) {
 $path=if($report -eq 'mongo'){'/api/inspections/analytics'}else{"/api/reports/${report}?from=$from&to=$to"}
 $null=Invoke-RestMethod "$Api$path" -Headers $headers
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $data=Invoke-RestMethod "$Api$path" -Headers $headers
 $watch.Stop()
 $count=if($report -eq 'mongo'){ @($data.porCategoria).Count+@($data.zonasPorMes).Count+@($data.incidenciasPorVehiculo).Count }else{@($data).Count}
 $results+="$report : $($watch.ElapsedMilliseconds) ms; $count filas"
}
$results | Set-Content -Encoding utf8 (Join-Path $PSScriptRoot '../docs/evidencias/supuestos-medicion.txt')
$results
