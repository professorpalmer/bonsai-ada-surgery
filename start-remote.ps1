# Cloudflare quick tunnel in front of local llama-server.
# Mac on any network: https://<trycloudflare>/v1  + Bearer token from artifacts/api_key.txt
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cf = Join-Path $Root 'bin\cloudflared.exe'
if (-not (Test-Path $Cf)) { throw "cloudflared.exe missing. Put it in $Cf" }
$Port = if ($env:BONSAI_PORT) { [int]$env:BONSAI_PORT } else { 8080 }
Write-Host "tunnel -> http://127.0.0.1:$Port"
& $Cf tunnel --no-autoupdate --url "http://127.0.0.1:$Port"
