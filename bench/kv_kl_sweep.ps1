param(
    [string]$Model = "models\Ternary-Bonsai-2-27B-PTQ1_0.gguf",
    [int]$Ctx = 16384,
    [int]$Chunks = 4,
    [string]$Bin = "$env:TEMP\combo-build\bin",
    [string]$Tag = "16k",
    # K:V pairs. Mixed types and iq4_nl are not on the CUDA flash-attention path (CPU fallback, ~10x slower).
    [string[]]$Configs = @('q8_0:q8_0', 'q4_0:q4_0', 'q8_0:q4_0')
)
# KV-cache precision sweep: KL divergence of quantized K/V caches against the same model with f16 K/V.
# Relative KL on one model is valid; KL against the repo "F16" GGUF is not (it is ternary re-expanded).
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$cu = "C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13"
$env:PATH = "$cu\bin;$cu\bin\x86_64;$env:PATH"
$out = "artifacts\eval"
New-Item -ItemType Directory -Force $out | Out-Null
$base = "$out\kl_base_f16kv_$Tag.bin"
$common = @('-m', $Model, '-f', "$out\wiki.test.raw", '-c', "$Ctx", '--chunks', "$Chunks", '-b', '2048', '-ub', '512', '-ngl', '99', '-fa', 'on')

if (-not (Test-Path $base)) {
    Write-Host "== base: f16 KV -> $base"
    & "$Bin\llama-perplexity.exe" @common -ctk f16 -ctv f16 --kl-divergence-base $base 2>&1 |
        Tee-Object -FilePath "$out\kl_f16_f16_$Tag.log" | Select-String -Pattern "estimate|Final|error|ETA" | Select-Object -Last 4
}
# mixed K/V types last: that combination misses the in-place flash-attention path and runs ~10x slower
foreach ($c in $Configs) {
    $k, $v = $c.Split(':')
    $log = "$out\kl_${k}_${v}_$Tag.log"
    if ((Test-Path $log) -and (Select-String -Path $log -Pattern "Mean\s+KLD" -Quiet)) {
        Write-Host "== K=$k V=$v (done, see $log)"
        continue
    }
    Write-Host "== K=$k V=$v"
    & "$Bin\llama-perplexity.exe" @common -ctk $k -ctv $v --kl-divergence --kl-divergence-base $base 2>&1 |
        Tee-Object -FilePath $log | Select-String -Pattern "Mean\s+KLD|Same top p|Mean ln|Maximum KLD|error" | ForEach-Object { $_.Line }
}
Write-Host "DONE kv kl sweep"
