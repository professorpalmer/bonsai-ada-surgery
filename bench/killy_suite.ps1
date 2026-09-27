param(
    [string]$Base = "http://127.0.0.1:8080",
    [string]$Tag = (Get-Date -Format 'yyyyMMdd'),
    [switch]$Quick   # first 20 problems per arm, for a smoke test
)
# Replays of Killy's HumanEval plates against a running start-server.ps1 (plate 035 "app or harness decides",
# plate "thinking mode x output cap"), plus the voxel pagoda plate. Every arm uses the server's own sampling
# (temperature 1.0, top-p 0.95, top-k 20), one seed, HumanEval 164 with the official tests executed.
#   medium     : chat_template_kwargs reasoning_effort=medium, cap 24576 (the server's -n)  -> his medium / no-cap cell
#   off        : enable_thinking=false, cap 24576                                            -> his "off" row
#   app-high   : what Cline / Kilo / Open WebUI send: top-level reasoning_effort "high", cap 256
#                (his 0/164 HTTP 500 row and the 17/164 quickstart row)                    -> harness-proofing
#   app-4096   : a coding harness with a 4096-token cap and no effort word (his Continue row, 137/164)
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$out = "artifacts\eval\killy_$Tag"
New-Item -ItemType Directory -Force $out | Out-Null
$limit = if ($Quick) { @('--limit', '20') } else { @() }
$arms = @(
    @{ n = 'medium';   a = @('--arm', 'medium', '--temp', '-1', '--max-tokens', '24576') },
    @{ n = 'off';      a = @('--arm', 'off', '--temp', '-1', '--max-tokens', '24576') },
    @{ n = 'app-high'; a = @('--arm', 'app', '--effort', 'high', '--temp', '-1', '--max-tokens', '256') },
    @{ n = 'app-4096'; a = @('--arm', 'app', '--temp', '-1', '--max-tokens', '4096') }
)
foreach ($arm in $arms) {
    Write-Host "== HumanEval $($arm.n)"
    python bench\humaneval_run.py --base $Base @($arm.a) @limit --out "$out\$($arm.n)" 2>&1 |
        Select-String -Pattern 'pass@1|error|Traceback' | ForEach-Object { $_.Line }
}
Write-Host "== pagoda plate"
python bench\pagoda_plate.py --base $Base --out "$out\pagoda" 2>&1
Write-Host "== summary"
Get-ChildItem "$out\*\summary.json" | ForEach-Object {
    $s = (Get-Content $_.FullName -Raw | ConvertFrom-Json).summary
    "{0,-9} {1,3}/{2}  ({3}%)  max_tokens={4} effort={5} {6}s" -f $_.Directory.Name, $s.passed, $s.n, $s.pass_at_1, $s.max_tokens, $s.effort, $s.seconds
}
