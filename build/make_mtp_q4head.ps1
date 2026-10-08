# Requantize the grafted MTP head (blk.64.*) from Q8_0 to Q4_0 for 8 GB cards. Run make_mtp_procreations.ps1 first.
# Output: models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations-q4head.gguf
# Proof: strip the head and the file hashes equal the official PTQ1_0 (same check as the graft).
param(
    [string]$Base = "models\Ternary-Bonsai-2-27B-PTQ1_0.gguf",
    [string]$Src = "models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf",
    [string]$Work = "models\donor"
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
if (-not (Test-Path $Src)) { throw "grafted file not found: $Src (run build\make_mtp_procreations.ps1)" }
if (-not (Test-Path "vendor\prism-llama\gguf-py")) { throw "vendor\prism-llama missing" }
$graft = Join-Path $Work "bonsai2-small-gpu"
if (-not (Test-Path (Join-Path $graft "graft\tools\merge.py"))) { throw "graft tools missing in $graft (run make_mtp_procreations.ps1)" }

$out = ($Src -replace '\.gguf$', '-q4head.gguf')
Write-Host "== requantizing blk.64.* Q8_0 -> Q4_0 -> $out"
python build\requant_mtp.py $Src $out
if ($LASTEXITCODE -ne 0) { throw "requant failed" }

Write-Host "== proof: strip the head and compare with the base"
$check = Join-Path $Work "q4head-strip-check.gguf"
python "$graft\graft\tools\merge.py" --strip $out $check
$a = (Get-FileHash $Base -Algorithm SHA256).Hash
$b = (Get-FileHash $check -Algorithm SHA256).Hash
Remove-Item $check
if ($a -ne $b) { throw "stripped file differs from the base: the requant changed Bonsai 2 bytes" }
Write-Host "stripped sha256 == base sha256 ($($a.ToLower()))"
