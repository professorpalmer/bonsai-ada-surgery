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
#
# Tiered KV (BONSAI_TIER, default on): the full 262144 window at q8_0 on 12 GB. Each attention layer keeps
# its first N cells of K/V in VRAM and the rest in pinned system RAM mapped into the same CUDA range
# (LLAMA_KV_VRAM_CELLS), so nothing pages and nothing changes below N: greedy output is bit-identical to an
# all-VRAM cache. Past N a step reads the RAM tail over PCIe (~20 GB/s), and there MTP drafting resumes
# with longer drafts (a verify reads the tail once for all its columns). N is sized at launch from free
# VRAM, leaving BONSAI_VRAM_MARGIN (default 1300 MiB) below the point where Windows starts demoting the
# cache and weights to shared memory. BONSAI_KV_VRAM_CELLS pins N. BONSAI_TIER=0 restores the plain
# all-VRAM cache (then use the 98304 window: 128k/q8_0 plus the draft context pages on 12 GB).
$Tier = $env:BONSAI_TIER -ne '0'
$Ctx = if ($env:BONSAI_CTX) { [int]$env:BONSAI_CTX } elseif ($Tier) { 262144 } else { 98304 }
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
# mean over code/prose/bash (87.5 vs 64.2 tok/s). GGML_CUDA_BATCH_INVARIANT=1 forces the
# planar PTQ1_0 path onto the warp-reduce epilogue so a token verified in a 2-4 column MTP
# batch matches a token decoded alone. The faster four-accumulator epilogue (flag off) can
# flip a late near-tie. Does not make every mmap close-token identical (see RECEIPTS.md).
$Spec = if ($env:BONSAI_SPEC) { [int]$env:BONSAI_SPEC } elseif ((Split-Path $Model -Leaf) -match '-mtp') { 2 } else { 0 }
# Drafting at every depth. The draft context keeps full history up to BONSAI_SPEC_DEPTH, then only a
# sliding window of the last BONSAI_DRAFT_WINDOW rows (LLAMA_SPEC_DRAFT_WINDOW): the MTP head predicts the
# next few tokens from recent context, so its cache stays small and in VRAM and each draft pass stays
# cheap however long the conversation gets. This replaces the old hard cutoff at 24k (measured then:
# draft about even at 24-32k, -27% at 64k), which predates the deep MMA attention path that reads K/V
# once for a whole verify batch. Measured 2026-09-27, genuine prefill, 4070: 32k 54.5 -> 103.6 tok/s,
# 64k 48.0 -> 90.1 (code) and 47.8 -> 72.4 (prose), same drafts accepted.
# Draft size by depth: BONSAI_SPEC below BONSAI_SPEC_DEPTH, BONSAI_SPEC_MID up to the tiered-KV VRAM line,
# BONSAI_SPEC_DEEP past it (a PCIe-bound step makes a wider verify nearly free: +26% code / +15% prose at
# 180k for 4 vs 2).
$SpecDepth = if ($env:BONSAI_SPEC_DEPTH) { [int]$env:BONSAI_SPEC_DEPTH } else { 24576 }
$DraftWindow = if ($env:BONSAI_DRAFT_WINDOW) { [int]$env:BONSAI_DRAFT_WINDOW } else { 16384 }
$SpecMid = if ($env:BONSAI_SPEC_MID) { [int]$env:BONSAI_SPEC_MID } else { 2 }
$SpecDeep = if ($env:BONSAI_SPEC_DEEP) { [int]$env:BONSAI_SPEC_DEEP } else { 4 }
[string[]]$SpecArgs = @()
if ($Spec -gt 0) {
    if (-not ((Split-Path $Model -Leaf) -match '-mtp')) { throw 'BONSAI_SPEC needs an *-mtp-*.gguf (grafted MTP head)' }
    $env:GGML_CUDA_BATCH_INVARIANT = '1'
    # Quantized-KV attention for <= 8 queries (decode and draft verify) on the MMA kernel at every depth: it
    # packs the 6 query heads that share a KV head into one tile and reads K/V once, where the vector kernel
    # reads them once per query head. Measured 2026-09-27: 4k 78.1 -> 86.9 tok/s, 16k 77.7 -> 111.6.
    # Caveat: like every stream-k attention launch, its KV split follows the padded KV length, so greedy
    # MTP-on output is not guaranteed bit-identical to MTP-off (rounding-level). 32768 restores the old gate.
    if (-not $env:GGML_CUDA_FA_DEEP_MMA) { $env:GGML_CUDA_FA_DEEP_MMA = '256' }
    $SpecArgs = @('--spec-type', 'draft-mtp', '--spec-draft-n-max', "$Spec", '-ctkd', $Ctk, '-ctvd', $Ctk)
    if ($SpecDepth -gt 0) {
        $SpecArgs += @('--spec-draft-depth-max', "$SpecDepth", '--spec-draft-depth-resume', "$SpecDepth", '--spec-draft-n-max-deep', "$SpecMid")
        $env:LLAMA_SPEC_DRAFT_WINDOW = "$DraftWindow"
    }
}

# Tiered KV sizing (see the recipe note above). Bytes per KV cell for Bonsai 2 27B: 16 attention layers x
# K+V x 4 heads x 256 dims; the draft (MTP) layer and the per-layer VRAM staging buffer are 1/16 of that.
$TierCells = 0
if ($Tier) {
    $CellBytes = switch ($Ctk) { 'q8_0' { 34816 } 'q4_0' { 18432 } 'f16' { 65536 } default { 34816 } }
    # Draft (MTP) context: its full-history prefix plus the sliding window, all in VRAM. The +2048+2*2048+256
    # is the server's batch slack.
    $DraftCells = if ($Spec -gt 0) { $SpecDepth + $DraftWindow + 2048 + 2 * 2048 + 256 } else { 0 }
    if ($env:BONSAI_KV_VRAM_CELLS) {
        $TierCells = [int]$env:BONSAI_KV_VRAM_CELLS
    } else {
        $FreeMiB = [int]((& nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | Select-Object -First 1).Trim())
        $Margin = if ($env:BONSAI_VRAM_MARGIN) { [int]$env:BONSAI_VRAM_MARGIN } else { 1300 }
        # weights (the token embedding stays in system RAM), recurrent state, compute buffers, CUDA context
        $FixedMiB = (Get-Item $Model).Length / 1MB - 265 + 150 + 400 + 300 + $DraftCells * $CellBytes / 16 / 1MB
        # KV head N*CellBytes plus the staging buffer (Ctx-N)*CellBytes/16 must fit in what is left
        $Budget = ($FreeMiB - $Margin - $FixedMiB) * 1MB - $Ctx * $CellBytes / 16
        $TierCells = [int]([math]::Floor($Budget / ($CellBytes * 15 / 16) / 256) * 256)
    }
    if ($TierCells -ge $Ctx) {
        $TierCells = 0   # the whole window fits: plain cache
    } elseif ($TierCells -lt 16384) {
        throw "Tiered KV: only $TierCells cells fit in VRAM. Free VRAM (close GPU apps), lower BONSAI_CTX, or set BONSAI_KV_VRAM_CELLS."
    }
}
if ($TierCells -gt 0) {
    $env:LLAMA_KV_VRAM_CELLS = "$TierCells"
    # Past the VRAM line, attention copies the used RAM tail into a VRAM staging buffer with the copy engine
    # first (prefill: once instead of once per query tile; decode: DMA instead of SMs reading over PCIe,
    # +28% decode at 180k on the 4070). Below the line nothing is copied.
    $env:GGML_CUDA_TIER_BOUNCE = '1'
    $env:GGML_CUDA_TIER_BOUNCE_DECODE = '1'
    Remove-Item Env:LLAMA_KV_VRAM_CELLS_DRAFT -ErrorAction SilentlyContinue
    if ($Spec -gt 0) {
        $env:LLAMA_SPEC_TAIL_DEPTH = "$TierCells"
        $env:LLAMA_SPEC_N_MAX_TAIL = "$SpecDeep"
    }
} else {
    Remove-Item Env:LLAMA_KV_VRAM_CELLS, Env:GGML_CUDA_TIER_BOUNCE, Env:GGML_CUDA_TIER_BOUNCE_DECODE, Env:LLAMA_KV_VRAM_CELLS_DRAFT, Env:LLAMA_SPEC_TAIL_DEPTH, Env:LLAMA_SPEC_N_MAX_TAIL -ErrorAction SilentlyContinue
}

Write-Host "model  $(Split-Path $Model -Leaf)"
Write-Host "window $Ctx / $Ctk  (trained max 262144)"
if ($TierCells -gt 0) { Write-Host "kv     tiered: cells 0..$TierCells in VRAM, $TierCells..$Ctx in system RAM (draft $SpecDeep past it)" }
Write-Host "listen 0.0.0.0:$Port  ctx=$Ctx  kv=$Ctk/$Ctk  fa=on  ngl=99  spec=$Spec/$SpecMid/$SpecDeep (draft window $DraftWindow past $SpecDepth)  think=$Think effort=$Effort budget=$ThinkBudget  backend-sampling=$($BsArgs.Count -gt 0)"
Write-Host "api    Authorization: Bearer <artifacts/api_key.txt>"
# Harness-proofing (BONSAI_HARNESS_PROOF, default on). The same weights score 0 to 160 of 164 on HumanEval
# depending only on what the client sends (Killy's plate 035). The server absorbs the two causes:
#   - an effort word the template rejects ("high": Cline, Kilo, Open WebUI -> HTTP 500 on every request)
#     becomes "medium";
#   - with thinking on, a client output cap below the think budget + 4096 (256 quickstart, 300
#     SillyTavern, 1024 AnythingLLM, 4096 Continue) is raised to it, so no app cuts the model off mid-think.
# BONSAI_NOTHINK_SAMPLING (e.g. "temperature=0.7,top_p=0.8,min_p=0") sets the sampling for thinking-off
# requests, for fields the client did not send.
#   - "low" and "xhigh" also become "medium" unless BONSAI_EFFORT_ALLOWED widens the set: medium beats both
#     at every output cap in Killy's HumanEval grid (plate 035: 160-161 vs 143-151 at 16k-32k-uncapped), and
#     PrismML's card says low is not really supported and behaves close to xhigh.
if ($env:BONSAI_HARNESS_PROOF -ne '0') {
    $env:LLAMA_EFFORT_ALLOWED = if ($env:BONSAI_EFFORT_ALLOWED) { $env:BONSAI_EFFORT_ALLOWED } else { 'medium' }
    # an explicit server default effort (BONSAI_EFFORT) is always allowed
    if ((",$($env:LLAMA_EFFORT_ALLOWED),") -notlike "*,$Effort,*") { $env:LLAMA_EFFORT_ALLOWED += ",$Effort" }
    $env:LLAMA_EFFORT_FALLBACK = 'medium'
    if ($ThinkBudget -ge 0) { $env:LLAMA_THINK_MAX_TOKENS_FLOOR = "$($ThinkBudget + 4096)" }
    # Off by default: the model card's non-thinking set (temperature 0.7, top_p 0.8, no presence penalty)
    # measured worse on bench\toolcall_stress.py than the thinking-mode sampling (2026-09-26, n=9 per arm:
    # parsed 6/9 vs 8/9, three payloads ran into the 9000-token cap vs one).
    if ($env:BONSAI_NOTHINK_SAMPLING) { $env:LLAMA_NOTHINK_SAMPLING = $env:BONSAI_NOTHINK_SAMPLING } else { Remove-Item Env:LLAMA_NOTHINK_SAMPLING -ErrorAction SilentlyContinue }
}
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
