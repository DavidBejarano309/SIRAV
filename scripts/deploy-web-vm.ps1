param([switch]$SkipBuild)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$runtime=Join-Path $root '.runtime/virtualbox'
Push-Location $root
try {
  if (!$SkipBuild) {
    & npm.cmd --prefix frontend run build
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la compilacion del frontend' }
  }
  $jar=Join-Path $root 'backend/target/sirav-api-1.0.0.jar'
  if (!(Test-Path -LiteralPath $jar)) { throw 'Compila el backend con mvn -f backend/pom.xml verify' }
  $stage=Join-Path $runtime ('web-stage-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path (Join-Path $stage 'frontend'),(Join-Path $stage 'backend') | Out-Null
  Copy-Item -Path 'frontend/dist/*' -Destination (Join-Path $stage 'frontend') -Recurse
  Copy-Item -LiteralPath $jar -Destination (Join-Path $stage 'backend/app.jar')
  $nginx=[IO.File]::ReadAllText((Join-Path $root 'frontend/nginx.conf')).Replace('http://backend:8080','http://127.0.0.1:8080').Replace('/usr/share/nginx/html','/opt/sirav/current/frontend')
  $nginx=$nginx.Replace('proxy_set_header Host $http_host;','proxy_set_header Host $http_host; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme;')
  [IO.File]::WriteAllText((Join-Path $stage 'nginx.conf'),$nginx.Replace("`r`n","`n"),(New-Object Text.UTF8Encoding($false)))
  & tar.exe -cf .runtime/virtualbox/web-bundle.tar -C $stage .
  if ($LASTEXITCODE -ne 0) { throw 'Fallo el empaquetado de la aplicacion' }
  & scp.exe -i .runtime/virtualbox/id_ed25519 -P 2223 -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=.runtime/virtualbox/known_hosts .runtime/virtualbox/web-bundle.tar sirav@127.0.0.1:web-bundle.tar
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo transferir la aplicacion a SIRAV-Web' }
  $remote=[IO.File]::ReadAllText((Join-Path $root 'deploy/virtualbox/deploy-web.sh')).Replace("`r`n","`n")
  $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
  & ssh.exe -i .runtime/virtualbox/id_ed25519 -p 2223 -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=.runtime/virtualbox/known_hosts sirav@127.0.0.1 "echo $encoded | base64 -d | sudo bash"
  if ($LASTEXITCODE -ne 0) { throw 'Fallo el despliegue; revisa -Action Diagnose en manage-web-vm.ps1' }
} finally { Pop-Location }
