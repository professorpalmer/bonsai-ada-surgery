# CRACK build, full 262k native window (q4_0 KV), OpenAI-compatible /v1, reachable off-LAN via a
# Cloudflare quick tunnel. Prints the public base URL and writes it to artifacts\remote_url.txt.
#
#   .\start-crack-remote.ps1              # server + tunnel, both minimized
#   client: base URL https://<tunnel>.trycloudflare.com/v1, model "bonsai-2-27b",
#           Authorization: Bearer <artifacts\api_key.txt>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

Get-Process llama-server, cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

$env:BONSAI_MODEL = if ($env:BONSAI_MODEL) { $env:BONSAI_MODEL } else { 'Bonsai-2-27B-PTQ1_0-CRACK.gguf' }
$env:BONSAI_CTX   = if ($env:BONSAI_CTX)   { $env:BONSAI_CTX }   else { '262144' }
$env:BONSAI_CTK   = if ($env:BONSAI_CTK)   { $env:BONSAI_CTK }   else { 'q4_0' }
$Port = if ($env:BONSAI_PORT) { [int]$env:BONSAI_PORT } else { 8080 }

Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Root\start-server.ps1`"" -WindowStyle Minimized
$ok = $false
foreach ($i in 1..240) {
    Start-Sleep -Milliseconds 500
    try { if ((Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 1).status -eq 'ok') { $ok = $true; break } } catch {}
}
if (-not $ok) { throw 'llama-server did not come up' }

$log = Join-Path $Root 'artifacts\cloudflared.log'
Remove-Item $log -Force -ErrorAction SilentlyContinue
$cf = Join-Path $Root 'bin\cloudflared.exe'
Start-Process $cf -ArgumentList "tunnel --no-autoupdate --url http://127.0.0.1:$Port" -WindowStyle Minimized -RedirectStandardError $log
$url = $null
foreach ($i in 1..60) {
    Start-Sleep -Seconds 1
    if (Test-Path $log) {
        $m = Select-String -Path $log -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' | Select-Object -First 1
        if ($m) { $url = $m.Matches[0].Value; break }
    }
}
if (-not $url) { throw "tunnel URL not found; see $log" }
Set-Content -Path (Join-Path $Root 'artifacts\remote_url.txt') -Value $url -NoNewline
Write-Host "model   $env:BONSAI_MODEL  ctx=$env:BONSAI_CTX kv=$env:BONSAI_CTK"
Write-Host "local   http://127.0.0.1:$Port/v1"
Write-Host "remote  $url/v1"
Write-Host "key     $(Get-Content (Join-Path $Root 'artifacts\api_key.txt') -Raw)"
