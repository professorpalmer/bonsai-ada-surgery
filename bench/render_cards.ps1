# Render the result cards (docs/cards/*.html, 1200x675 CSS pixels) to 2400x1350 PNGs with headless Edge/Chrome.
# Each card keeps its numbers in one DATA object at the top of its HTML: edit DATA, then run this script.
# Usage: bench\render_cards.ps1            (every card)
#        bench\render_cards.ps1 decode     (only the cards whose name matches)
param([string]$Only = '')
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Cards = Join-Path $Root 'docs\cards'
$Browser = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Browser) { throw 'Edge or Chrome is needed for headless rendering' }
# card source, query, output PNG (repo-relative). The tier pages get the tier-first render (?focus=...).
$Jobs = @(
    @('scorecard', '',             'docs\img\scorecard.png'),
    @('decode',    '?focus=12gb',  'docs\12gb\img\decode.png'),
    @('prefill',   '?focus=12gb',  'docs\12gb\img\prefill.png'),
    @('vram',      '?focus=12gb',  'docs\12gb\img\vram.png'),
    @('decode',    '?focus=8gb',   'docs\8gb\img\decode.png'),
    @('prefill',   '?focus=8gb',   'docs\8gb\img\prefill.png'),
    @('vram',      '?focus=8gb',   'docs\8gb\img\vram.png'),
    @('saved',     '',             'docs\agents-layer\img\saved.png'),
    @('agentic',   '',             'docs\agents-layer\img\agentic.png'),
    @('quality',   '',             'docs\quality\img\quality.png')
)
$ErrorActionPreference = 'Continue'   # the browser reports "bytes written" on stderr
$Profile = Join-Path $env:TEMP 'bonsai-render-cards'
foreach ($j in $Jobs) {
    if ($Only -and $j[0] -notmatch $Only) { continue }
    $html = Join-Path $Cards "$($j[0]).html"
    $png = Join-Path $Root $j[2]
    New-Item -ItemType Directory -Force (Split-Path $png) | Out-Null
    & $Browser --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=1200,675 --virtual-time-budget=6000 `
        --allow-file-access-from-files "--user-data-dir=$Profile" "--screenshot=$png" `
        ("file:///" + ($html -replace '\\', '/') + $j[1]) 2>$null | Out-Null
    Write-Host ("{0,-38} {1,6:N0} KB" -f $j[2], ((Get-Item $png).Length / 1KB))
}
