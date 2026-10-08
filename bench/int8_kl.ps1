# int8 score step quality check: KL by token of the int8 kernel against today's kernel, same model, q8_0 K/V.
#   bench\int8_kl.ps1 -Int8Bin <dir> [-Ctx 32768] [-Chunks 2]   -> artifacts\eval\int8_kl_<ctx>.log
param(
    [Parameter(Mandatory)] [string]$Int8Bin,
    [string]$BaseBin = "bin",
    [string]$Model = "models\Ternary-Bonsai-2-27B-PTQ1_0.gguf",
    [int]$Ctx = 32768,
    [int]$Chunks = 2
)
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$cu = "C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13"
$env:PATH = "$cu\bin;$cu\bin\x86_64;$env:PATH"
$out = "artifacts\eval"
$base = "$out\int8kl_base_q8kv_$Ctx.bin"
$common = @('-m', $Model, '-f', "$out\wiki.test.raw", '-c', "$Ctx", '--chunks', "$Chunks", '-b', '2048', '-ub', '512', '-ngl', '99', '-fa', 'on', '-ctk', 'q8_0', '-ctv', 'q8_0')
if (-not (Test-Path $base)) {
    & "$BaseBin\llama-perplexity.exe" @common --kl-divergence-base $base 2>&1 | Out-File -Encoding utf8 "$out\int8kl_base_$Ctx.log"
    Select-String -Path "$out\int8kl_base_$Ctx.log" -Pattern "Final estimate" | Select-Object -Last 1
}
& "$Int8Bin\llama-perplexity.exe" @common --kl-divergence-base $base --kl-divergence 2>&1 | Out-File -Encoding utf8 "$out\int8_kl_$Ctx.log"
Select-String -Path "$out\int8_kl_$Ctx.log" -Pattern "Mean\s+KLD|Same top p|RMS .p|Maximum KLD|99.9%\s+KLD|Mean PPL" | ForEach-Object { $_.Line.Trim() }
