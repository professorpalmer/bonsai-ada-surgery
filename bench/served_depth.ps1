# Served decode / prefill / TTFT by context depth for one llama-server build.
# Starts the server from -Bin with the repo recipe flags, runs bench\quick_tps.py at each depth, stops it.
#
#   bench\served_depth.ps1 -Bin tooling\stock-bin -Model models\Ternary-Bonsai-2-27B-PTQ1_0.gguf -Tag prism
#   bench\served_depth.ps1 -Bin bin -Model models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf -Spec 2 -Tag bundle
#
# Output: artifacts\eval\served_<Tag>.txt (quick_tps lines per depth). Depths are approximate token counts.
param(
    [Parameter(Mandatory)] [string]$Bin,
    [Parameter(Mandatory)] [string]$Model,
    [string]$Tag = 'run',
    [int]$Ctx = 131072,
    [string]$Ctk = 'q8_0',
    [int]$Spec = 0,
    [int]$SpecDepthMax = 0,              # --spec-draft-depth-max (0 = draft at any depth)
    [string]$Depths = '0,32000,100000',   # comma-separated so it also works via `powershell -File`
    [int]$Port = 8897,
    [switch]$BackendSampling
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Bin = if ([IO.Path]::IsPathRooted($Bin)) { $Bin } else { Join-Path $Root $Bin }
$Model = if ([IO.Path]::IsPathRooted($Model)) { $Model } else { Join-Path $Root $Model }
$Key = (Get-Content (Join-Path $Root 'artifacts\api_key.txt') -Raw).Trim()
$Out = Join-Path $Root "artifacts\eval\served_$Tag.txt"
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null

[string[]]$SpecArgs = @()
if ($Spec -gt 0) {
    $env:GGML_CUDA_BATCH_INVARIANT = '1'
    $SpecArgs = @('--spec-type', 'draft-mtp', '--spec-draft-n-max', "$Spec", '-ctkd', $Ctk, '-ctvd', $Ctk)
    if ($SpecDepthMax -gt 0) { $SpecArgs += @('--spec-draft-depth-max', "$SpecDepthMax") }
}
[string[]]$BsArgs = @()
if ($BackendSampling) { $BsArgs += '--backend-sampling' }
$ServerArgs = @('-m', $Model, '-ngl', '99', '-fa', 'on', '-c', "$Ctx", '-np', '1', '-b', '2048', '-ub', '512',
    '-ctk', $Ctk, '-ctv', $Ctk, '--host', '127.0.0.1', '--port', "$Port", '--jinja', '--prio', '2', '--poll', '100',
    '--api-key', $Key, '--temp', '1.0', '--top-p', '0.95', '--top-k', '20') + $SpecArgs + $BsArgs

Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2
$log = Join-Path $Root "artifacts\eval\served_$Tag.server.log"
$p = Start-Process (Join-Path $Bin 'llama-server.exe') -ArgumentList $ServerArgs -WorkingDirectory $Bin -RedirectStandardError $log -RedirectStandardOutput "$log.out" -PassThru -NoNewWindow
try {
    $ok = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep 5
        if ($p.HasExited) { throw "server exited early, see $log" }
        try { if ((Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3).status -eq 'ok') { $ok = $true; break } } catch {}
    }
    if (-not $ok) { throw 'server did not become healthy' }
    "# $Tag  bin=$Bin  model=$(Split-Path $Model -Leaf)  ctx=$Ctx kv=$Ctk spec=$Spec spec-depth-max=$SpecDepthMax bs=$($BackendSampling.IsPresent)  $(Get-Date -Format s)" | Set-Content $Out
    foreach ($d in ($Depths -split ',' | ForEach-Object { [int]$_.Trim() })) {
        "## depth $d" | Add-Content $Out
        $lines = & python (Join-Path $Root 'bench\quick_tps.py') --base "http://127.0.0.1:$Port" --key-file (Join-Path $Root 'artifacts\api_key.txt') --depth $d 2>&1
        $lines | ForEach-Object { "$_" } | Add-Content $Out
        $lines | ForEach-Object { Write-Host "[$Tag d=$d] $_" }
    }
    $vram = (& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits).Trim()
    "vram_used_mib $vram" | Add-Content $Out
    Write-Host "[$Tag] VRAM in use: $vram MiB"
} finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
}
