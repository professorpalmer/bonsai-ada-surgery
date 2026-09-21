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
if ($env:BONSAI_MODEL) {
    # explicit pick, e.g. BONSAI_MODEL=Bonsai-2-27B-PTQ1_0-CRACK.gguf
    $p = if ([IO.Path]::IsPathRooted($env:BONSAI_MODEL)) { $env:BONSAI_MODEL } else { Join-Path $Root "models\$($env:BONSAI_MODEL)" }
    if (-not (Test-Path $p)) { throw "BONSAI_MODEL not found: $p" }
    $Model = $p
}
foreach ($pair in @(
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf'); Min = 6390000000 },
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf'); Min = 6290000000 },
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0.gguf'); Min = 5900000000 },
        @{ Path = (Join-Path $Root 'models\Bonsai-2-27B-PTQ1_0-CRACK-mtp-lean.gguf'); Min = 6290000000 },
        @{ Path = (Join-Path $Root 'models\Bonsai-2-27B-PTQ1_0-CRACK.gguf'); Min = 5900000000 },
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PQ2_0.gguf'); Min = 7100000000 },
        @{ Path = (Join-Path $Root 'models\Bonsai-2-27B-PQ2_0-CRACK.gguf'); Min = 7100000000 }
    )) {
    if ($Model) { break }
    $Model = Select-CompleteGguf $pair.Path $pair.Min
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

# Context / KV recipe. Default is the quality recipe: 96k window with q8_0 K/V. Measured on this
# model at 16k depth against f16 K/V (docs/QUALITY.md): q8_0 KL 0.00017, top-1 token agrees 99.4%;
# q4_0 KL 0.00218, top-1 agrees 97.9% (one flipped token in 48).
# Why 96k and not 128k on 12 GB: 128k/q8_0 with the draft context allocates fine (11.96 GB) but
# Windows starts paging the cache to system memory and decode at 32k depth falls from 47 to 30 tok/s.
# 96k/q8_0 sits at 10.8 GB and holds speed at every depth. Alternatives on 12 GB: BONSAI_CTX=131072
# BONSAI_CTK=q4_0 (9.9 GB, q4_0 noise); the full 262144 window needs q4_0 AND BONSAI_SPEC=0 (the
# draft context pushes it over the paging line). 16 GB+ cards: 262144 with q8_0.
$Ctx = if ($env:BONSAI_CTX) { [int]$env:BONSAI_CTX } else { 98304 }
$Ctk = if ($env:BONSAI_CTK) { $env:BONSAI_CTK } else { 'q8_0' }
$Port = if ($env:BONSAI_PORT) { [int]$env:BONSAI_PORT } else { 8080 }
# Chat-template reasoning. The GGUF template does three different things:
#   enable_thinking false -> emits <think></think> and the model answers immediately
#   effort xhigh (template default if unset) -> extra "think carefully..." system line; runaway
#   effort medium -> thinking ON, no extra instruction (the model's natural think)
#   effort low -> thinking ON plus "keep it brief..."
# Killy's MBPP/HumanEval: medium loses to think-off at a 10k output cap and beats it from 20k up
# (the gap to the 27B teacher is the budget, not the weights). Chat default is therefore medium
# with a 20k think cap. Agent harnesses: BONSAI_THINK=0.
$Effort = if ($env:BONSAI_EFFORT) { $env:BONSAI_EFFORT } else { 'medium' }
$Think = $env:BONSAI_THINK -ne '0'
$TemplateKwargs = if ($Think) { "{\`"reasoning_effort\`":\`"$Effort\`"}" } else { "{\`"reasoning_effort\`":\`"$Effort\`",\`"enable_thinking\`":false}" }
# Hard stop on <think> tokens, then the answer starts. 4096 crushed medium (same failure as a 10k
# generation cap). 20480 is the first cap where Killy's medium scores beat think-off. -1 = unlimited.
$ThinkBudget = if ($env:BONSAI_THINK_BUDGET) { [int]$env:BONSAI_THINK_BUDGET } else { 20480 }
# Injected before </think> when the budget trips, so a force-close still yields the drawing/code
# instead of an empty content field (Killy's SVG "reasoning madness" blanks).
$ThinkBudgetMsg = if ($null -ne $env:BONSAI_THINK_BUDGET_MSG) { $env:BONSAI_THINK_BUDGET_MSG } else { 'Now produce the complete answer.' }
# GPU-side sampling (--backend-sampling): saves the host round trip per token. Requests that carry a
# grammar (tools, json_schema) fall back to CPU sampling automatically. BONSAI_BS=0 disables.
[string[]]$BsArgs = @()
if ($env:BONSAI_BS -ne '0') { $BsArgs += '--backend-sampling' }   # typed: a one-element array would otherwise collapse to a string and splat per character

# Speculative decoding with a grafted MTP head (files named *-mtp-*.gguf carry blk.64).
# Prefers ProCreations' on-policy Q8 head (mtp-procreations) over the Qwen 3.8 teacher
# graft (mtp-lean): +4.3 pp draft acceptance / +3.9% tok/s on the paired 4070 probe.
# BONSAI_SPEC = draft n-max (0 = off). Default 2 for MTP files: on the RTX 4070 that is the best
# mean over code/prose/bash (87.5 vs 64.2 tok/s). GGML_CUDA_BATCH_INVARIANT=1 makes the
# one-column and multi-column PTQ1_0 kernels use identical arithmetic, so greedy output with the
# draft head is byte-identical to greedy output without it (verified with verify_identity.py).
$Spec = if ($env:BONSAI_SPEC) { [int]$env:BONSAI_SPEC } elseif ((Split-Path $Model -Leaf) -match '-mtp') { 2 } else { 0 }
# Stop drafting past this depth (--spec-draft-depth-max). Deep in the context a step is bound by
# reading the KV cache and the draft passes only add to it: on the 4070 the draft is +85% at zero
# depth, about even at 24-32k, and -27% at 64k. With the cutoff: 101 / 48 / 37 tok/s at 0 / 32k / 64k.
$SpecDepth = if ($env:BONSAI_SPEC_DEPTH) { [int]$env:BONSAI_SPEC_DEPTH } else { 24576 }
[string[]]$SpecArgs = @()
if ($Spec -gt 0) {
    if (-not ((Split-Path $Model -Leaf) -match '-mtp')) { throw 'BONSAI_SPEC needs an *-mtp-*.gguf (grafted MTP head)' }
    $env:GGML_CUDA_BATCH_INVARIANT = '1'
    $SpecArgs = @('--spec-type', 'draft-mtp', '--spec-draft-n-max', "$Spec", '-ctkd', $Ctk, '-ctvd', $Ctk)
    if ($SpecDepth -gt 0) { $SpecArgs += @('--spec-draft-depth-max', "$SpecDepth") }
}

Write-Host "model  $(Split-Path $Model -Leaf)"
Write-Host "window $Ctx / $Ctk  (trained max 262144; 12 GB default 98304/q8_0, full 262144/q4_0 with BONSAI_SPEC=0)"
Write-Host "listen 0.0.0.0:$Port  ctx=$Ctx  kv=$Ctk/$Ctk  fa=on  ngl=99  spec=$Spec (to depth $SpecDepth)  think=$Think effort=$Effort budget=$ThinkBudget  backend-sampling=$($BsArgs.Count -gt 0)"
Write-Host "api    Authorization: Bearer <artifacts/api_key.txt>"
[string[]]$BudgetMsgArgs = @()
if ($ThinkBudget -ge 0 -and $ThinkBudgetMsg) { $BudgetMsgArgs = @('--reasoning-budget-message', $ThinkBudgetMsg) }
Set-Location $Bin
& .\llama-server.exe @SpecArgs @BsArgs @BudgetMsgArgs `
    --chat-template-kwargs $TemplateKwargs `
    --reasoning-budget $ThinkBudget `
    -n 24576 `
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
