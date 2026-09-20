# Build Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf: PrismML's ternary file plus the Qwen 3.8 27B
# MTP (next-token prediction) head, which is what --spec-type draft-mtp drafts with.
#
# The graft tools are sudoingX's (https://github.com/sudoingX/bonsai2-small-gpu, graft/tools);
# this script only wires them up for Windows and avoids the 16 GB donor download by pulling the
# 15 blk.64 tensors (about 1 GB) out of the donor GGUF with surgery/hf_sparse_fetch.py.
#
# Output: 6,297,658,848 bytes, 866 tensors. Every Bonsai 2 tensor keeps its bytes and offset; only
# blk.64.* and a few header keys (nextn_predict_layers, block_count 65, graft.* provenance) are
# added, which the script proves by stripping the head again and hashing the result against the
# original. The whole-file hash varies with the graft.* provenance keys, so it is not compared.
#
# usage: .\build\make_mtp_lean.ps1 [-Base models\Ternary-Bonsai-2-27B-PTQ1_0.gguf]
param(
    [string]$Base = "models\Ternary-Bonsai-2-27B-PTQ1_0.gguf",
    [string]$Donor = "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q4_K_M.gguf",
    [string]$Work = "models\donor"
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
if (-not (Test-Path $Base)) { throw "base model not found: $Base (download Ternary-Bonsai-2-27B-PTQ1_0.gguf from prism-ml on Hugging Face)" }
if (-not (Test-Path "vendor\prism-llama\gguf-py")) { throw "vendor\prism-llama missing (git clone -b bonsai-combo https://github.com/professorpalmer/llama.cpp-ada-ternary vendor\prism-llama)" }
New-Item -ItemType Directory -Force $Work | Out-Null

$graft = Join-Path $Work "bonsai2-small-gpu"
if (-not (Test-Path $graft)) {
    git clone --depth 1 https://github.com/sudoingX/bonsai2-small-gpu $graft
}

$sparse = Join-Path $Work "Qwen3.8-27B-UD-Q4_K_M.sparse.gguf"
if (-not (Test-Path $sparse)) {
    Write-Host "== fetching blk.64.* from the donor (sparse, ~1 GB of a 16 GB file)"
    python surgery\hf_sparse_fetch.py $Donor $sparse "blk.64."
}

$head = Join-Path $Work "qwen38-27b-nextn-head-lean.gguf"
Write-Host "== extracting the head (no embed table: Bonsai 2 keeps its own, the fork applies the Hadamard inverse)"
python "$graft\graft\tools\extract_head.py" $sparse $head --no-embed-tokens

$out = ($Base -replace '\.gguf$', '-mtp-lean.gguf')
Write-Host "== merging -> $out"
python "$graft\graft\tools\merge.py" $Base $head $out

$len = (Get-Item $out).Length
Write-Host "size   $len (expect 6297658848)"

Write-Host "== proof: strip the head again and compare with the base file"
$check = Join-Path $Work "strip-check.gguf"
python "$graft\graft\tools\merge.py" --strip $out $check
$a = (Get-FileHash $Base -Algorithm SHA256).Hash
$b = (Get-FileHash $check -Algorithm SHA256).Hash
Remove-Item $check
if ($a -ne $b) { throw "stripped file differs from the base: the graft changed Bonsai 2 bytes, do not use $out" }
Write-Host "stripped sha256 == base sha256 ($($a.ToLower()))"
Write-Host "done. start-server.ps1 picks *-mtp-lean.gguf first and enables --spec-type draft-mtp."
