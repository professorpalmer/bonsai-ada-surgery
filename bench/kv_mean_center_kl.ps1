param(
    [string]$Model = "models\Ternary-Bonsai-2-27B-PTQ1_0.gguf",
    [string]$Bin = "$env:TEMP\combo-build\bin",
    [int]$CalibChunks = 64,
    [string]$Tag = "16k"
)
# K-cache mean-centering on top of the default Hadamard KV rotation: calibrate a per-(kv-head, channel) K
# bias on wikitext-2 *train*, then score q4_0/q4_0 and q8_0/q8_0 with the bias against the f16-KV base on
# wikitext-2 *test* (same method and base file as bench\kv_kl_sweep.ps1, so the numbers line up with it).
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$cu = "C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13"
$env:PATH = "$cu\bin;$cu\bin\x86_64;$env:PATH"
$out = "artifacts\eval"
$bias = "$out\kv-mean-center-bonsai2.gguf"
$base = "$out\kl_base_f16kv_$Tag.bin"
if (-not (Test-Path $base)) { throw "missing ${base}: run bench\kv_kl_sweep.ps1 first" }

if (-not (Test-Path $bias)) {
    Write-Host "== calibrate K bias on wiki.train ($CalibChunks x 512 tokens, q4_0 K so rotation is on)"
    & "$Bin\llama-kv-mean-center.exe" -m $Model -f "$out\wiki.train.raw" -o $bias -c 512 --chunks $CalibChunks -ngl 99 -fa on -ctk q4_0 -ctv q4_0 2>&1 |
        Select-String -Pattern "error|wrote|saved|layers" | Select-Object -Last 5
}
$common = @('-m', $Model, '-f', "$out\wiki.test.raw", '-c', '16384', '--chunks', '4', '-b', '2048', '-ub', '512', '-ngl', '99', '-fa', 'on')
foreach ($t in 'q4_0', 'q8_0') {
    $log = "$out\kl_${t}_${t}_meancenter_$Tag.log"
    Write-Host "== K=$t V=$t + mean-center"
    & "$Bin\llama-perplexity.exe" @common -ctk $t -ctv $t --kv-mean-center $bias --kl-divergence --kl-divergence-base $base 2>&1 |
        Tee-Object -FilePath $log | Select-String -Pattern "Mean\s+KLD|Same top p|Maximum KLD|error" | ForEach-Object { $_.Line }
}
Write-Host "reference (bench\kv_kl_sweep.ps1): q8_0 KLD 0.00017 top-1 99.38% / q4_0 KLD 0.00218 top-1 97.93%"
