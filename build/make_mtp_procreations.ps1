# Graft ProCreations' on-policy MTP head onto official PTQ1_0.
# Sparse-fetches blk.64.* from their PQ2_0+MTP GGUF (~450 MB), never the 7.6 GB trunk.
# Output: models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf
# Proof: strip the head and the file hashes equal the official PTQ1_0.
param(
    [string]$Base = "models\Ternary-Bonsai-2-27B-PTQ1_0.gguf",
    [string]$Donor = "https://huggingface.co/ProCreations/Ternary-Bonsai-2-27B-MTP/resolve/main/Ternary-Bonsai-2-27B-PQ2_0-MTP-Q8_0.gguf",
    [string]$Work = "models\donor"
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
if (-not (Test-Path $Base)) { throw "base model not found: $Base" }
if (-not (Test-Path "vendor\prism-llama\gguf-py")) { throw "vendor\prism-llama missing" }
New-Item -ItemType Directory -Force $Work | Out-Null

$graft = Join-Path $Work "bonsai2-small-gpu"
if (-not (Test-Path (Join-Path $graft "graft\tools\extract_head.py"))) {
    git clone --depth 1 https://github.com/sudoingX/bonsai2-small-gpu $graft
}

$sparse = Join-Path $Work "procreations-pq2-mtp.sparse.gguf"
if (-not (Test-Path $sparse)) {
    Write-Host "== fetching blk.64.* from ProCreations PQ2+MTP (sparse)"
    python surgery\hf_sparse_fetch.py $Donor $sparse "blk.64."
}

$head = Join-Path $Work "procreations-mtp-head-q8.gguf"
Write-Host "== extracting the trained head (no embed table)"
python "$graft\graft\tools\extract_head.py" $sparse $head --no-embed-tokens

$out = ($Base -replace '\.gguf$', '-mtp-procreations.gguf')
Write-Host "== merging -> $out"
python "$graft\graft\tools\merge.py" $Base $head $out

Write-Host "== proof: strip the head and compare with the base"
$check = Join-Path $Work "procreations-strip-check.gguf"
python "$graft\graft\tools\merge.py" --strip $out $check
$a = (Get-FileHash $Base -Algorithm SHA256).Hash
$b = (Get-FileHash $check -Algorithm SHA256).Hash
Remove-Item $check
if ($a -ne $b) { throw "stripped file differs from the base: the graft changed Bonsai 2 bytes" }
Write-Host "stripped sha256 == base sha256 ($($a.ToLower()))"
Write-Host "done. A/B with: python bench\mtp_head_ab.py"
