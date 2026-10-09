# Bonsai 2 27B server (LAN + localhost): the full 262,144-token window with q8_0 K/V on a 12 GB card.
# Every default below is measured on an RTX 4070 12 GB; the receipts are in docs/Q8_FULL_CONTEXT.md.
$ErrorActionPreference = 'Stop'
# Variables set in this window before the launcher runs. A value left over from an earlier test (BONSAI_SPEC=0 is the
# common one) silently changes the server; the launcher prints them all at start (issue #7).
$UserEnv = @(Get-ChildItem Env: | Where-Object { $_.Name -match '^(BONSAI_|LLAMA_ARG_|GGML_)' } | Sort-Object Name)
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bin = Join-Path $Root 'bin'
function Select-CompleteGguf([string]$Path, [int64]$MinBytes) {
    if (-not (Test-Path $Path)) { return $null }
    if ((Get-Item $Path).Length -lt $MinBytes) { return $null }
    return $Path
}
# 8 GB cards (docs/8GB.md): q4_0 K/V, a 131k window, the Q4_0 MTP head with draft 1 / tail 1 when its file is present,
# the shared CUDA pool and f16 prefill. Detected from total VRAM; BONSAI_8GB=1 forces it, BONSAI_8GB=0 turns it off.
$TotalMiB = [int]((& nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | Select-Object -First 1).Trim())
$Small = if ($env:BONSAI_8GB) { $env:BONSAI_8GB -eq '1' } else { $TotalMiB -le 8704 }
$Model = $null
if ($env:BONSAI_MODEL) {
    # explicit pick, e.g. BONSAI_MODEL=Bonsai-2-27B-PTQ1_0-CRACK.gguf
    $p = if ([IO.Path]::IsPathRooted($env:BONSAI_MODEL)) { $env:BONSAI_MODEL } else { Join-Path $Root "models\$($env:BONSAI_MODEL)" }
    if (-not (Test-Path $p)) { throw "BONSAI_MODEL not found: $p" }
    $Model = $p
}
$Candidates = @(
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf'); Min = 6390000000 },
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf'); Min = 6290000000 },
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0.gguf'); Min = 5900000000 },
        @{ Path = (Join-Path $Root 'models\Bonsai-2-27B-PTQ1_0-CRACK-mtp-lean.gguf'); Min = 6290000000 },
        @{ Path = (Join-Path $Root 'models\Bonsai-2-27B-PTQ1_0-CRACK.gguf'); Min = 5900000000 },
        @{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PQ2_0.gguf'); Min = 7100000000 },
        @{ Path = (Join-Path $Root 'models\Bonsai-2-27B-PQ2_0-CRACK.gguf'); Min = 7100000000 }
    )
if ($Small) {
    # build\make_mtp_q4head.ps1: the same graft with the head requantized to Q4_0 (-214 MiB on the card)
    $Candidates = @(@{ Path = (Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations-q4head.gguf'); Min = 6180000000 }) + $Candidates
}
foreach ($pair in $Candidates) {
    if ($Model) { break }
    $Model = Select-CompleteGguf $pair.Path $pair.Min
}
if (-not $Model) { throw 'No complete Bonsai 2 GGUF in models\' }

# ---- Vision projector (optional) ------------------------------------------------------------------------
# BONSAI_MMPROJ=<file in models\ or a full path> (Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf from prism-ml); llama-server's
# own LLAMA_ARG_MMPROJ is picked up the same way. Default: the encoder runs on the CPU (--no-mmproj-offload) and takes
# no VRAM from the cache; an image costs a few seconds more to encode. BONSAI_MMPROJ_GPU=1 puts it on the card and
# the VRAM line is sized with its measured cost. A projector the sizing did not know about over-commits the card:
# Windows then moves buffers to system RAM and prefill collapses (issue #4: 1,117 -> 198 tok/s at 16k).
$Mmproj = if ($env:BONSAI_MMPROJ) { $env:BONSAI_MMPROJ } elseif ($env:LLAMA_ARG_MMPROJ) { $env:LLAMA_ARG_MMPROJ } else { $null }
[string[]]$MmprojArgs = @()
$MmprojMiB = 0
if ($Mmproj) {
    if (-not [IO.Path]::IsPathRooted($Mmproj)) { $Mmproj = Join-Path $Root "models\$Mmproj" }
    if (-not (Test-Path $Mmproj)) { throw "vision projector not found: $Mmproj" }
    Remove-Item Env:LLAMA_ARG_MMPROJ -ErrorAction SilentlyContinue   # passed explicitly below
    $MmprojGpu = $env:BONSAI_MMPROJ_GPU -eq '1'
    $MmprojArgs = @('--mmproj', $Mmproj)
    # GPU: count the file size. Measured 346 MiB at load for the 600 MiB Q8_0 file (receipts/vision_probe.log), so this
    # over-counts a little, on the safe side.
    if ($MmprojGpu) { $MmprojMiB = [int]((Get-Item $Mmproj).Length / 1MB) } else { $MmprojArgs += '--no-mmproj-offload' }
}
$Server = Join-Path $Bin 'llama-server.exe'
if (-not (Test-Path $Server)) { throw "llama-server.exe missing in $Bin" }

# What this build can do. Binaries from before the tiered-KV runtime (older Releases zips, the plain #221
# branch) do not know --kv-vram-cells: they get the previous all-VRAM recipe (96k window) below.
$Help = (& $Server --help 2>&1 | Out-String)
$HasTier = $Help -match '--kv-vram-cells'
$HasHarness = $Help -match '--reasoning-effort-allow'

$ApiKeyFile = Join-Path $Root 'artifacts\api_key.txt'
if (-not (Test-Path $ApiKeyFile)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $ApiKeyFile) | Out-Null
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    Set-Content -Path $ApiKeyFile -Value (-join ($bytes | ForEach-Object { $_.ToString('x2') })) -NoNewline
}
$ApiKey = (Get-Content -Path $ApiKeyFile -Raw).Trim()

# ---- Context and KV precision ------------------------------------------------------------------------
# q8_0 K/V: 1 flipped top token in 160 at depth vs 1 in 48 for q4_0 (KL 0.00017 vs 0.00218, docs/QUALITY.md).
# Tiered KV (--kv-vram-cells N): each attention layer keeps cells [0, N) in VRAM and the rest in pinned
# system RAM mapped into the same CUDA range. Nothing pages and output is bit-identical to an all-VRAM cache;
# past N a step reads the RAM tail over PCIe (the runtime stages it into VRAM with the copy engine first).
# N is sized at launch from free VRAM, BONSAI_VRAM_MARGIN below the point where Windows demotes a background
# server to shared memory (1300 MiB with the display on this card, 1000 with it on an iGPU; see below).
# BONSAI_KV_VRAM_CELLS pins N. BONSAI_TIER=0 (or an older binary): the all-VRAM cache in a 96k window
# (128k/q8_0 plus the draft context pages on 12 GB).
$Tier = ($env:BONSAI_TIER -ne '0') -and $HasTier
$Ctx = if ($env:BONSAI_CTX) { [int]$env:BONSAI_CTX } elseif ($Small) { 131072 } elseif ($Tier) { 262144 } else { 98304 }
# 8 GB: q4_0 holds 2.3x the positions of q8_0 in the same VRAM (1 flipped top token in 48 at depth vs 1 in 171)
$Ctk = if ($env:BONSAI_CTK) { $env:BONSAI_CTK } elseif ($Small) { 'q4_0' } else { 'q8_0' }
$Port = if ($env:BONSAI_PORT) { [int]$env:BONSAI_PORT } else { 8080 }

# ---- Reasoning ------------------------------------------------------------------------------------------
# The GGUF template: enable_thinking false -> <think></think>, the model answers at once; effort xhigh (the
# template default) -> an extra "think carefully" line and runaway thinking; medium -> the model's natural
# thinking; low -> behaves close to xhigh (PrismML's card). Killy's HumanEval grid (plate 035): medium beats
# thinking-off from a 2k cap up and beats low and xhigh at every cap (160-161 of 164 at 8k-uncapped).
# Chat default: medium with a 20k thinking budget. Tool-calling agents send enable_thinking=false per request
# (bench\toolcall_stress.py: 8/9 parsed thinking-off vs 6/9 at medium, which spent 10-17k tokens thinking).
$Effort = if ($env:BONSAI_EFFORT) { $env:BONSAI_EFFORT } else { 'medium' }
$Think = $env:BONSAI_THINK -ne '0'
# Passed through the environment, not the command line: Windows PowerShell 5.1 and PowerShell 7.3+ quote
# embedded double quotes differently for native programs, and no single escaping of a JSON argument works
# on both (issue #1). llama-server reads LLAMA_ARG_CHAT_TEMPLATE_KWARGS verbatim.
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = if ($Think) { '{"reasoning_effort":"' + $Effort + '"}' } else { '{"reasoning_effort":"' + $Effort + '","enable_thinking":false}' }
$ThinkBudget = if ($env:BONSAI_THINK_BUDGET) { [int]$env:BONSAI_THINK_BUDGET } else { 20480 }
# default output cap for requests without max_tokens: the think budget plus room for the answer (24576 at 20480).
# A request that sends its own larger reasoning_budget_tokens gets budget + 4096 from the server (engine 113db541a).
$NPredict = [Math]::Max(24576, $ThinkBudget + 4096)
# injected before </think> when the budget trips, so a force-close still yields the answer
$ThinkBudgetMsg = if ($null -ne $env:BONSAI_THINK_BUDGET_MSG) { $env:BONSAI_THINK_BUDGET_MSG } else { 'Now produce the complete answer.' }
[string[]]$BudgetMsgArgs = @()
if ($ThinkBudget -ge 0 -and $ThinkBudgetMsg) { $BudgetMsgArgs = @('--reasoning-budget-message', $ThinkBudgetMsg) }

# Harness-proofing (BONSAI_HARNESS_PROOF=0 turns it off). The same weights score 0 to 160 of 164 depending on
# what the client sends. "high" (Cline, Kilo, Open WebUI) raises in the template -> HTTP 500: every effort
# word except BONSAI_EFFORT_ALLOWED (default medium) becomes medium. With thinking on, a client output cap
# below the think budget + 4096 (256 quickstart, 300 SillyTavern, 1024 AnythingLLM, 4096 Continue) is raised
# to it, so no app ends the request mid-think.
[string[]]$HarnessArgs = @()
if ($env:BONSAI_HARNESS_PROOF -ne '0' -and $HasHarness) {
    $Allow = if ($env:BONSAI_EFFORT_ALLOWED) { $env:BONSAI_EFFORT_ALLOWED } else { 'medium' }
    if ((",$Allow,") -notlike "*,$Effort,*") { $Allow += ",$Effort" }   # the server's own default is always allowed
    $HarnessArgs = @('--reasoning-effort-allow', $Allow, '--reasoning-effort-fallback', 'medium')
    if ($ThinkBudget -ge 0) { $HarnessArgs += @('--reasoning-max-tokens-floor', "$($ThinkBudget + 4096)") }
}

# GPU-side sampling: saves the host round trip per token; requests with a grammar (tools, json_schema) fall
# back to CPU sampling automatically. BONSAI_BS=0 disables.
[string[]]$BsArgs = @()
if ($env:BONSAI_BS -ne '0') { $BsArgs += '--backend-sampling' }   # typed: a one-element array would otherwise splat per character

# ---- Speculative decoding (grafted MTP head, *-mtp-*.gguf) ----------------------------------------------
# ProCreations' on-policy Q8 head is preferred over the Qwen 3.8 teacher graft (+4.3 pp acceptance).
# BONSAI_SPEC = draft size (0 = off), 2 by default: best over code/prose at shallow depth (3 is +3% on code,
# -6% on prose at 16k). Drafting runs at every depth: the draft context keeps only the last BONSAI_DRAFT_WINDOW
# rows (16k), so a draft pass costs the same at any depth, and quantized-KV decode runs on the MMA attention
# kernel, so a verify batch reads K/V once (32k 54.5 -> 103.6 tok/s, 64k 48.0 -> 90.1). Past the tiered-KV
# line the draft size is BONSAI_SPEC_DEEP (4): a PCIe-bound step makes each extra verify column nearly free
# (+26% code, +15% prose at 180k).
# GGML_CUDA_BATCH_INVARIANT=1 keeps the PTQ1_0 mat-vec per-column arithmetic independent of the batch width
# (a verified token matches it decoded alone) at no measurable cost. Attention is not batch-invariant under
# drafting (its KV split follows the kernel instance and the padded KV length): MTP-on output can differ from
# MTP-off at the rounding level. Older binaries: drafting stops at 24k (BONSAI_SPEC_DEPTH), as measured then.
$Spec = if ($env:BONSAI_SPEC) { [int]$env:BONSAI_SPEC } elseif ((Split-Path $Model -Leaf) -match '-mtp') { if ($Small) { 1 } else { 2 } } else { 0 }
# 8 GB: tail 1. The recurrent-state rollback ring is sized max(draft, tail); tail 2 holds one more 150 MiB plane.
$SpecDeep = if ($env:BONSAI_SPEC_DEEP) { [int]$env:BONSAI_SPEC_DEEP } elseif ($Small) { 1 } else { 4 }
$Ubatch = if ($env:BONSAI_UBATCH) { [int]$env:BONSAI_UBATCH } elseif ($Small -and $Spec -eq 0) { 1024 } else { 512 }
if ($Small) {
    # engine switches (ignored by older binaries): a smaller draft micro-batch, and f16 prefill from pool memory up to
    # the depth the margin holds. Not the shared CUDA pool (GGML_CUDA_SHARED_POOL): with MTP drafting it gave 1-token
    # answers to fresh long prompts on the RTX 2060 SUPER (60k: 3 of 3 with it, 0 of 3 without, PR #9).
    if ($Spec -gt 0) {
        if (-not $env:LLAMA_MTP_DRAFT_UBATCH) { $env:LLAMA_MTP_DRAFT_UBATCH = '256' }
    }
    if (-not $env:GGML_CUDA_FA_PREFILL_F16) { $env:GGML_CUDA_FA_PREFILL_F16 = if ($Spec -gt 0) { '32768' } else { '65536' } }
    # The fixed costs below were measured with these switches. An older engine ignores them, and then the VRAM line
    # is too high for the card: Windows moves memory out of VRAM and prefill collapses. Say so before the start.
    $Has8gb = $false
    try { $Has8gb = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $Bin 'ggml-cuda.dll'))).Contains('GGML_CUDA_SHARED_POOL') } catch { }
    if (-not $Has8gb) {
        Write-Host "warn   8 GB preset: this engine does not have the 8 GB switches (shared pool, f16 prefill)."
        Write-Host "       The VRAM line can then be too high for the card, and prefill can collapse. Unzip the latest"
        Write-Host "       bonsai-bundle-win-x64.zip (bundle-20261007-8gb or later) over the repository, then start again."
    }
}
$DraftWindow = if ($env:BONSAI_DRAFT_WINDOW) { [int]$env:BONSAI_DRAFT_WINDOW } else { 16384 }
[string[]]$SpecArgs = @()
$DraftCells = 0
if ($Spec -gt 0) {
    if (-not ((Split-Path $Model -Leaf) -match '-mtp')) { throw 'BONSAI_SPEC needs an *-mtp-*.gguf (grafted MTP head)' }
    $env:GGML_CUDA_BATCH_INVARIANT = '1'
    # Lookup drafting (patch 0039): a lookup drafter in front of the MTP head drafts text that is already in the
    # context (file rewrites, edit calls, quoted logs) up to BONSAI_LOOKUP_N tokens; the head drafts new text with its
    # own small draft size. Measured (receipts/lookup_ab.jsonl, same text in every arm): file rewrites 117 -> 352 tok/s
    # at 4k and 63 -> 164 at 130k, edit calls +19% / +25%, plain text unchanged. 32 is the best limit for edit calls;
    # 64 is faster on full rewrites (420 / 183) and slower on edits. BONSAI_LOOKUP=0 turns it off.
    # 8 GB (RTX 2060 SUPER, drafting preset, receipts/lookup_ab_8gb.jsonl): file rewrites 58 -> 126 tok/s at depth 0
    # and 32 -> 69 at 64k, edits +6 % / +16 %, plain unchanged, same text at depth 0. Lowest free VRAM 82 MiB with
    # lookup, 90 MiB without it at the same depth: lookup adds about 8 MiB.
    # BONSAI_SPEC_TYPE: the whole --spec-type list (overrides the above). BONSAI_SPEC_ARGS: extra drafter flags.
    $HasLookupCap = $Help -match '--spec-lookup-n-max'
    $LookupN = if ($env:BONSAI_LOOKUP_N) { [int]$env:BONSAI_LOOKUP_N } else { 32 }
    $LookupOn = ($env:BONSAI_LOOKUP -ne '0') -and $HasLookupCap -and $LookupN -gt 0
    $SpecType = if ($env:BONSAI_SPEC_TYPE) { $env:BONSAI_SPEC_TYPE } elseif ($LookupOn) { 'ngram-mod,draft-mtp' } else { 'draft-mtp' }
    $SpecArgs = @('--spec-type', $SpecType, '--spec-draft-n-max', "$Spec", '-ctkd', $Ctk, '-ctvd', $Ctk)
    if ($LookupOn -and -not $env:BONSAI_SPEC_TYPE) { $SpecArgs += @('--spec-lookup-n-max', "$LookupN") }
    if ($env:BONSAI_SPEC_ARGS) { $SpecArgs += @($env:BONSAI_SPEC_ARGS -split '\s+' | Where-Object { $_ }) }
    if ($HasTier) {
        $SpecArgs += @('--spec-draft-window', "$DraftWindow")
        $DraftCells = $DraftWindow + 2 * 2048 + 256   # the draft context the runtime sizes for the window
    } else {
        $SpecDepth = if ($env:BONSAI_SPEC_DEPTH) { [int]$env:BONSAI_SPEC_DEPTH } else { 24576 }
        $SpecArgs += @('--spec-draft-depth-max', "$SpecDepth")
    }
}

# ---- Tiered KV sizing -----------------------------------------------------------------------------------
# Bytes per KV cell for Bonsai 2 27B: 16 attention layers x K+V x 4 heads x 256 dims; the draft (MTP) layer
# and the per-layer VRAM staging buffer are 1/16 of that.
$TierCells = 0
[string[]]$TierArgs = @()
if ($Tier) {
    $CellBytes = switch ($Ctk) { 'q8_0' { 34816 } 'q4_0' { 18432 } 'f16' { 65536 } default { 34816 } }
    if ($env:BONSAI_KV_VRAM_CELLS) {
        $TierCells = [int]$env:BONSAI_KV_VRAM_CELLS
    } else {
        $FreeMiB = [int]((& nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | Select-Object -First 1).Trim())
        # With the display on this card the desktop keeps growing its VRAM share under the server: 1300 MiB held,
        # 800 did not. With the display on the iGPU (nvidia-smi display_active Disabled) 1000 held a 10-minute
        # soak at 83 / 107 tok/s (4k / 16k) and 600 paged at once. Measured on the 4070, 2026-09-27.
        $Headless = ((& nvidia-smi --query-gpu=display_active --format=csv,noheader | Select-Object -First 1).Trim()) -eq 'Disabled'
        # Under WDDM nvidia-smi can report Disabled for a card that draws the desktop (2060 SUPER, driver 591.86:
        # display_active Disabled, display_attached No, 4K desktop on it). Windows reports a desktop resolution only
        # on adapters with a display, so a resolution on this card's adapter means it is not headless.
        $GpuName = (& nvidia-smi --query-gpu=name --format=csv,noheader | Select-Object -First 1).Trim()
        # Exception: with the desktop on the iGPU, Windows reports the desktop resolution on both adapters (RTX 4070 and
        # UHD 770 both 1920, 2026-10-07), while nvidia-smi correctly says Disabled. So the Windows check overrides
        # nvidia-smi only when no other adapter reports a display.
        $Video = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        $Adapters = @($Video | Where-Object { $_.Name -eq $GpuName })
        $OtherDisplays = @($Video | Where-Object { $_.Name -ne $GpuName -and $_.CurrentHorizontalResolution })
        if ($Adapters.Count -eq 1 -and $Adapters[0].CurrentHorizontalResolution -and $OtherDisplays.Count -eq 0) { $Headless = $false }
        $Margin = if ($env:BONSAI_VRAM_MARGIN) { [int]$env:BONSAI_VRAM_MARGIN } elseif ($Headless) { 1000 } else { 1300 }
        # weights (the token embedding stays in system RAM), recurrent state, compute buffers, CUDA context
        $FixedMiB = (Get-Item $Model).Length / 1MB - 265 + 150 + 400 + 300 + $DraftCells * $CellBytes / 16 / 1MB + $MmprojMiB
        if ($Small) {
            # measured on an RTX 2060 SUPER with the desktop on it (docs/8GB.md): the server's fixed cost per mode
            # and the free VRAM that held (drafting: 225 MiB; no head: 400, room for the f16 prefill copy at 64k)
            $FixedMiB = if ($Spec -gt 0) { 6531 + $MmprojMiB } elseif ($Ubatch -ge 1024) { 6218 + $MmprojMiB } else { 5955 + $MmprojMiB }
            $Margin = if ($env:BONSAI_VRAM_MARGIN) { [int]$env:BONSAI_VRAM_MARGIN } elseif ($Spec -gt 0) { 225 } else { 400 }
        }
        # KV head N*CellBytes plus the staging buffer (Ctx-N)*CellBytes/16 must fit in what is left
        $Budget = ($FreeMiB - $Margin - $FixedMiB) * 1MB - $Ctx * $CellBytes / 16
        $TierCells = [int]([math]::Floor($Budget / ($CellBytes * 15 / 16) / 256) * 256)
    }
    if ($TierCells -ge $Ctx) {
        $TierCells = 0   # the whole window fits: plain cache
    } elseif ($TierCells -lt 16384) {
        throw "Tiered KV: only $TierCells cells fit in VRAM. Free VRAM (close GPU apps), lower BONSAI_CTX, or set BONSAI_KV_VRAM_CELLS."
    }
    if ($TierCells -gt 0) {
        $TierArgs = @('--kv-vram-cells', "$TierCells")
        if ($Spec -gt 0) { $SpecArgs += @('--spec-draft-n-max-tail', "$SpecDeep") }
    }
}

if ($Small) { Write-Host "8gb    preset on ($TotalMiB MiB card; BONSAI_8GB=0 turns it off): ub $Ubatch, f16 prefill to $($env:GGML_CUDA_FA_PREFILL_F16) cells" }
Write-Host "model  $(Split-Path $Model -Leaf)"
Write-Host "window $Ctx / $Ctk  (trained max 262144)"
if ($TierCells -gt 0) { Write-Host "kv     tiered: cells 0..$TierCells in VRAM, $TierCells..$Ctx in system RAM$(if ($Margin) { " (VRAM margin $Margin MiB)" })" }
if (-not $HasTier) { Write-Host "note   this llama-server predates the tiered-KV runtime: 96k all-VRAM recipe (see README, Quick start)" }
if ($Spec -gt 0) {
    Write-Host "spec   draft $Spec$(if ($TierCells -gt 0) { " ($SpecDeep past the VRAM line)" })$(if ($HasTier) { ", draft window $DraftWindow" }) (MTP on)$(if ($LookupOn -and -not $env:BONSAI_SPEC_TYPE) { "; lookup drafting up to $LookupN (BONSAI_LOOKUP=0 turns it off)" } elseif ($SpecType -ne 'draft-mtp') { "; types $SpecType" })$(if ($env:BONSAI_SPEC_ARGS) { " $($env:BONSAI_SPEC_ARGS)" })"
} elseif ($env:BONSAI_SPEC) {
    Write-Host "spec   draft 0: MTP is OFF because BONSAI_SPEC=$($env:BONSAI_SPEC) is set in this window. Decode is slower:"
    Write-Host "       at 138k context, 25 tok/s with MTP against 11.6 without (RTX 4070, receipts/issue7_repro.log)."
    Write-Host "       To turn MTP on: Remove-Item Env:BONSAI_SPEC (or open a new window), then start again."
    Write-Host "       With MTP off, the server warns 'model has unused tensor blk.64...': that is the MTP head, not an error."
} else {
    Write-Host "spec   draft 0: MTP is off because $(Split-Path $Model -Leaf) has no MTP head. For faster decode, use the"
    Write-Host "       *-mtp-*.gguf file (README, Quick start)."
}
# Variables the launcher sets itself. It removes them when it stops (finally block below). A window that ran an
# older launcher can still hold them, so they are not listed as the user's settings either.
$LauncherVars = @('BONSAI_LAYER_KEY', 'LLAMA_ARG_CHAT_TEMPLATE_KWARGS', 'GGML_CUDA_BATCH_INVARIANT',
                  'GGML_CUDA_SHARED_POOL', 'LLAMA_MTP_DRAFT_UBATCH', 'GGML_CUDA_FA_PREFILL_F16')
$Listed = @($UserEnv | Where-Object { $_.Name -notin $LauncherVars -and $_.Value })
if ($Listed.Count -gt 0) {
    Write-Host ("env    set in this window, these change the defaults: " + (($Listed | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '  '))
    Write-Host "       A new PowerShell window starts without them. Remove-Item Env:NAME removes one."
}
Write-Host "listen 0.0.0.0:$Port  think=$Think effort=$Effort budget=$ThinkBudget  harness-proofing=$($HarnessArgs.Count -gt 0)  backend-sampling=$($BsArgs.Count -gt 0)"
Write-Host "api    Authorization: Bearer <artifacts/api_key.txt>"
if ($Mmproj) { Write-Host "vision $(Split-Path $Mmproj -Leaf) on the $(if ($MmprojGpu) { "GPU ($MmprojMiB MiB counted in the VRAM line)" } else { "CPU (no VRAM; BONSAI_MMPROJ_GPU=1 to offload)" })" }

# ---- Bonsai layer (BONSAI_LAYER=0 turns it off) ------------------------------------------------------------
# A small server-side layer in front of llama-server, on the same port clients already use. For coding requests
# it adds exact API cards for the Python modules involved (generated from the sandbox runtime) and checks the
# model's code for names that do not exist; for plain requests without client tools it gives the model a
# sandboxed Python tool (CPython on WASI: no host files, network or processes). Clients need no changes.
# Measured: research/quality-20260929/REPORT.md. Needs Python 3 and layer\fetch_runtime.ps1 run once; without
# them the plain server starts as before.
$LayerDir = Join-Path $Root 'layer'
$Layer = $env:BONSAI_LAYER -ne '0'
if ($Layer) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    $rt = Test-Path (Join-Path $LayerDir 'runtime\bin\python-3.12.0.wasm')
    $wt = $false
    if ($py) { & python -c "import wasmtime" 2>$null; $wt = ($LASTEXITCODE -eq 0) }
    if (-not ($py -and $rt -and $wt)) {
        Write-Host "layer  off: run layer\fetch_runtime.ps1 once to enable it (python=$([bool]$py) runtime=$rt wasmtime=$wt)"
        $Layer = $false
    }
}
$ListenHost = '0.0.0.0'; $ListenPort = $Port; $LayerProc = $null
if ($Layer) {
    $InnerPort = if ($env:BONSAI_INNER_PORT) { [int]$env:BONSAI_INNER_PORT } else { $Port + 10000 }
    $ListenHost = '127.0.0.1'; $ListenPort = $InnerPort
    $env:BONSAI_LAYER_KEY = $ApiKey   # the layer rejects wrong keys before doing any work
    $LayerProc = Start-Process python -PassThru -WindowStyle Hidden -ArgumentList @(
        ('"' + (Join-Path $LayerDir 'bonsai_layer.py') + '"'), '--host', '0.0.0.0', '--port', "$Port",
        '--upstream', "http://127.0.0.1:$InnerPort")
    Remove-Item Env:BONSAI_LAYER_KEY
    Write-Host "layer  on: clients use :$Port (API cards, API check, sandboxed Python); llama-server on 127.0.0.1:$InnerPort"
}
# Another app busy on this GPU (rendering or computing on the card) slows the server even when it uses no VRAM:
# Windows time-slices the GPU between them, and MTP drafting (many short kernels per token) loses the most. Measured
# by Milor123 (issue #4): 56 -> 83 tok/s at 16k after moving kdeconnect-app.exe to the iGPU. Warn, never block.
try {
    $Busy = 0
    foreach ($i in 1..6) {
        $u = [int]((& nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | Select-Object -First 1).Trim())
        if ($u -gt $Busy) { $Busy = $u }
        Start-Sleep -Milliseconds 250
    }
    if ($Busy -ge 10) {
        $Apps = (& nvidia-smi) | Select-String '^\|\s+\d+\s+\S+\s+\S+\s+\d+\s+(C\+G|G|C)\s+(\S+)' | ForEach-Object { Split-Path $_.Matches[0].Groups[2].Value -Leaf } | Where-Object { $_ -ne 'llama-server.exe' } | Sort-Object -Unique
        Write-Host ("warn   the GPU is {0}% busy before the server starts: one of these apps is working on this card: {1}. Drafting slows when the GPU is shared;" -f $Busy, ($Apps -join ', '))
        Write-Host "       close it or set it to the integrated GPU (Settings > System > Display > Graphics), then restart."
    }
} catch { }
# The launcher sizes the GPU memory itself (the VRAM line above). The engine's own automatic fit has nothing to adjust
# with every layer set, and it only printed "failed to fit params to free device memory ... abort". Turn it off.
[string[]]$FitArgs = if ($Help -match '--fit ') { @('--fit', 'off') } else { @() }
Set-Location $Bin
try {
& .\llama-server.exe @TierArgs @SpecArgs @BsArgs @BudgetMsgArgs @HarnessArgs @MmprojArgs @FitArgs `
    --reasoning-budget $ThinkBudget `
    -n $NPredict `
    -m $Model `
    -ngl 99 `
    -fa on `
    -c $Ctx `
    -np 1 `
    -b 2048 `
    -ub $Ubatch `
    -ctk $Ctk `
    -ctv $Ctk `
    --host $ListenHost `
    --port $ListenPort `
    --alias bonsai-2-27b `
    --jinja `
    --prio 2 `
    --poll 100 `
    --metrics `
    --api-key $ApiKey `
    --temp 1.0 `
    --top-p 0.95 `
    --top-k 20
} finally {
    if ($LayerProc -and -not $LayerProc.HasExited) { Stop-Process -Id $LayerProc.Id -Force -ErrorAction SilentlyContinue }
    # Remove the variables this run set, so that the next start in this window begins from the user's own settings
    # (the 8 GB preset only sets a switch when it is not already set; a value left from an earlier run would stay).
    $Mine = @($UserEnv | ForEach-Object { $_.Name })
    foreach ($n in $LauncherVars) {
        if ($Mine -notcontains $n) { Remove-Item "Env:$n" -ErrorAction SilentlyContinue }
    }
}
