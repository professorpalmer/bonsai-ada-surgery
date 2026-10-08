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

Write-Host "== proof: every tensor outside blk.64 is byte-identical to the source file"
# A whole-file hash of the stripped file matches the base only when the metadata matches; a file with this
# repository's chat template embedded differs in metadata, so the proof compares the tensor bytes.
python bench\gguf_tensor_identity.py $Src $out --ignore-prefix blk.64.
if ($LASTEXITCODE -ne 0) { throw "a tensor outside the MTP head differs: the requant changed Bonsai 2 bytes" }
Write-Host "all tensors outside blk.64 byte-identical; done: $out"
