# Render the shareable result cards (docs/img/cards.html, 1200x675) to 2400x1350 PNGs with headless Edge/Chrome.
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Html = Join-Path $Root 'docs\img\cards.html'
$Browser = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Browser) { throw 'Edge or Chrome is needed for headless rendering' }
$ErrorActionPreference = 'Continue'   # the browser reports "bytes written" on stderr
foreach ($c in 'summary', 'decode', 'prefill', 'kv', 'killy', 'igpu', 'identity', 'pagoda', 'upgrades') {
    $png = Join-Path $Root "docs\img\$c.png"
    & $Browser --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=1200,675 --virtual-time-budget=4000 `
        "--screenshot=$png" ("file:///" + ($Html -replace '\\', '/') + "?c=$c") 2>$null | Out-Null
    Write-Host ("{0,-9} {1,6:N0} KB" -f $c, ((Get-Item $png).Length / 1KB))
}
# The slab: every card in one tall image (docs/img/mega.html), 2488 x 4384 at 1x.
$Mega = Join-Path $Root 'docs\img\mega.html'; $png = Join-Path $Root 'docs\img\mega.png'
& $Browser --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=2488,4384 --virtual-time-budget=8000 `
    "--screenshot=$png" ("file:///" + ($Mega -replace '\\', '/')) 2>$null | Out-Null
Write-Host ("{0,-9} {1,6:N0} KB" -f 'mega', ((Get-Item $png).Length / 1KB))
