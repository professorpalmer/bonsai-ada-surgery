# llama-bench PP512 + TG64 at KV depths. Transferable Ada/hybrid measurement.
$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Bin = Join-Path $Root 'bin'
$Candidates = @(
    (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0.gguf'),
    (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PQ2_0.gguf'),
    (Join-Path $Root 'models\Bonsai-2-27B-PQ2_0-CRACK.gguf')
)
$Model = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Model) { throw 'No GGUF to bench' }
$Out = Join-Path $Root 'artifacts\depth_sweep.json'
New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null
Set-Location $Bin
Write-Host "depth sweep $(Split-Path $Model -Leaf)"
& .\llama-bench.exe -m $Model -ngl 99 -fa on -p 512 -n 64 -d 0,4096,16384,32768 -r 2 -o json |
    Tee-Object -FilePath $Out
Write-Host "wrote $Out"
