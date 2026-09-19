# Official PrismML Bonsai 2 27B LAN + localhost server.
# Prefers PTQ1_0 (Ada-faster, 5.95 GB) so more of the 12 GB 4070 is KV/context.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bin = Join-Path $Root 'bin'
function Select-CompleteGguf([string]$Path, [int64]$MinBytes) {
    if (-not (Test-Path $Path)) { return $null }
    if ((Get-Item $Path).Length -lt $MinBytes) { return $null }
    return $Path
}
$Model = $null
foreach ($pair in @(
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0.gguf'); Min = 5900000000 },
        @{ Path = (Join-Path $Root 'models\Bonsai-2-27B-PTQ1_0-CRACK.gguf'); Min = 5900000000 },
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PQ2_0.gguf'); Min = 7100000000 },
        @{ Path = (Join-Path $Root 'models\Bonsai-2-27B-PQ2_0-CRACK.gguf'); Min = 7100000000 }
    )) {
    $Model = Select-CompleteGguf $pair.Path $pair.Min
    if ($Model) { break }
}
if (-not $Model) { throw 'No complete Bonsai 2 GGUF in models\' }
if (-not (Test-Path (Join-Path $Bin 'llama-server.exe'))) { throw "llama-server.exe missing in $Bin" }

$ApiKeyFile = Join-Path $Root 'artifacts\api_key.txt'
if (-not (Test-Path $ApiKeyFile)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $ApiKeyFile) | Out-Null
    $key = -join ((48..57) + (97..102) | Get-Random -Count 48 | ForEach-Object { [char]$_ })
    Set-Content -Path $ApiKeyFile -Value $key -NoNewline
}
$ApiKey = (Get-Content -Path $ApiKeyFile -Raw).Trim()

$Ctx = if ($env:BONSAI_CTX) { [int]$env:BONSAI_CTX } else { 65536 }
$Ctk = if ($env:BONSAI_CTK) { $env:BONSAI_CTK } else { 'q8_0' }
$Port = if ($env:BONSAI_PORT) { [int]$env:BONSAI_PORT } else { 8080 }

Write-Host "model  $(Split-Path $Model -Leaf)"
Write-Host "listen 0.0.0.0:$Port  ctx=$Ctx  kv=$Ctk/$Ctk  fa=on  ngl=99"
Write-Host "api    Authorization: Bearer <artifacts/api_key.txt>"
Set-Location $Bin
& .\llama-server.exe `
    -m $Model `
    -ngl 99 `
    -fa on `
    -c $Ctx `
    -np 1 `
    -b 2048 `
    -ub 512 `
    -ctk $Ctk `
    -ctv $Ctk `
    --host 0.0.0.0 `
    --port $Port `
    --alias bonsai-2-27b `
    --jinja `
    --prio 2 `
    --poll 100 `
    --metrics `
    --api-key $ApiKey `
    --temp 1.0 `
    --top-p 0.95 `
    --top-k 20
