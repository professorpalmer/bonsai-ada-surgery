# Bonsai 2 small models (2B / 4B / 9B) on the Bonsai serving stack: all-VRAM q8_0 cache at the trained 262k window,
# harness-proofing, reasoning budget with a forced close, backend sampling, the optional layer. No MTP head exists for
# these files, so no drafting. 
#
#   BONSAI_SMALL_MODEL=C:\Users\<user>\models\bonsai2-small\9B\Ternary-Bonsai-2-9B-PTQ1_0.gguf .\start-small.ps1
#
#   BONSAI_SMALL_BIN      bin folder with llama-server.exe (default: ..\bonsai-2-27b-serve\bin)
#   BONSAI_SMALL_PORT     public port (default 8090); llama-server listens on port+10000 when the layer is on
#   BONSAI_CTX            262144      BONSAI_CTK q8_0      BONSAI_UBATCH 1024
#   BONSAI_EFFORT         medium      BONSAI_EFFORT_ALLOWED medium     BONSAI_THINK 1    BONSAI_THINK_BUDGET 20480
#   BONSAI_HARNESS_PROOF  1           BONSAI_BS 1 (backend sampling)   BONSAI_LAYER 1
#   BONSAI_PRESENCE       0.0         presence penalty (Tester A's loop finding: 1.5 on the 9B)
#   BONSAI_TEMPLATE       path        chat template file (default: the GGUF's embedded template)
#   BONSAI_LOG_FILE       path        server log; BONSAI_STDERR_FILE path keeps raw stderr (asserts)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bin = if ($env:BONSAI_SMALL_BIN) { $env:BONSAI_SMALL_BIN } else { Join-Path (Split-Path -Parent $Root) 'bonsai-2-27b-serve\bin' }
$Server = Join-Path $Bin 'llama-server.exe'
if (-not (Test-Path $Server)) { throw "llama-server.exe missing in $Bin" }
if (-not $env:BONSAI_SMALL_MODEL) { throw 'BONSAI_SMALL_MODEL=<path to a Ternary-Bonsai-2-{2B,4B,9B}-*.gguf> is required' }
$Model = $env:BONSAI_SMALL_MODEL
if (-not (Test-Path $Model)) { throw "model not found: $Model" }
$Help = (& $Server --help 2>&1 | Out-String)
$HasHarness = $Help -match '--reasoning-effort-allow'
$HasPackedMask = $Help -match '--kq-mask-packed'

$Ctx = if ($env:BONSAI_CTX) { [int]$env:BONSAI_CTX } else { 262144 }
$Ctk = if ($env:BONSAI_CTK) { $env:BONSAI_CTK } else { 'q8_0' }
$UBatch = if ($env:BONSAI_UBATCH) { [int]$env:BONSAI_UBATCH } else { 1024 }
$Port = if ($env:BONSAI_SMALL_PORT) { [int]$env:BONSAI_SMALL_PORT } else { 8090 }
$Presence = if ($env:BONSAI_PRESENCE) { $env:BONSAI_PRESENCE } else { '0.0' }

$Effort = if ($env:BONSAI_EFFORT) { $env:BONSAI_EFFORT } else { 'medium' }
$Think = $env:BONSAI_THINK -ne '0'
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = if ($Think) { '{"reasoning_effort":"' + $Effort + '"}' } else { '{"reasoning_effort":"' + $Effort + '","enable_thinking":false}' }
$ThinkBudget = if ($env:BONSAI_THINK_BUDGET) { [int]$env:BONSAI_THINK_BUDGET } else { 20480 }
$ThinkBudgetMsg = if ($null -ne $env:BONSAI_THINK_BUDGET_MSG) { $env:BONSAI_THINK_BUDGET_MSG } else { 'Now produce the complete answer.' }
[string[]]$BudgetArgs = @('--reasoning-budget', "$ThinkBudget")
if ($ThinkBudget -ge 0 -and $ThinkBudgetMsg) { $BudgetArgs += @('--reasoning-budget-message', $ThinkBudgetMsg) }
[string[]]$HarnessArgs = @()
if ($env:BONSAI_HARNESS_PROOF -ne '0' -and $HasHarness) {
    $Allow = if ($env:BONSAI_EFFORT_ALLOWED) { $env:BONSAI_EFFORT_ALLOWED } else { 'medium' }
    if ((",$Allow,") -notlike "*,$Effort,*") { $Allow += ",$Effort" }
    $HarnessArgs = @('--reasoning-effort-allow', $Allow, '--reasoning-effort-fallback', 'medium')
    if ($ThinkBudget -ge 0) { $HarnessArgs += @('--reasoning-max-tokens-floor', "$($ThinkBudget + 4096)") }
}
[string[]]$BsArgs = @(); if ($env:BONSAI_BS -ne '0') { $BsArgs += '--backend-sampling' }
[string[]]$MaskArgs = @(); if ($HasPackedMask -and $env:BONSAI_KQ_MASK_PACKED -ne '0') { $MaskArgs += '--kq-mask-packed' }
[string[]]$TemplateArgs = @(); if ($env:BONSAI_TEMPLATE) { $TemplateArgs = @('--chat-template-file', $env:BONSAI_TEMPLATE) }
[string[]]$LogArgs = @()
if ($env:BONSAI_LOG_FILE) { $lf = if ([IO.Path]::IsPathRooted($env:BONSAI_LOG_FILE)) { $env:BONSAI_LOG_FILE } else { Join-Path $Root $env:BONSAI_LOG_FILE }; New-Item -ItemType Directory -Force (Split-Path $lf) | Out-Null; $LogArgs = @('--log-file', $lf) }
$env:GGML_CUDA_BATCH_INVARIANT = '1'

$ApiKeyFile = Join-Path $Root 'artifacts\api_key.txt'
if (-not (Test-Path $ApiKeyFile)) {
    New-Item -ItemType Directory -Force (Split-Path $ApiKeyFile) | Out-Null
    $bytes = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    Set-Content -Path $ApiKeyFile -Value (-join ($bytes | ForEach-Object { $_.ToString('x2') })) -NoNewline
}
$ApiKey = (Get-Content -Path $ApiKeyFile -Raw).Trim()

# ---- the layer (BONSAI_LAYER=0 turns it off) ----
$LayerDir = Join-Path $Root 'layer'
$Layer = $env:BONSAI_LAYER -ne '0'
if ($Layer) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    $rt = Test-Path (Join-Path $LayerDir 'runtime\bin\python-3.12.0.wasm')
    $wt = $false; if ($py) { & python -c "import wasmtime" 2>$null; $wt = ($LASTEXITCODE -eq 0) }
    if (-not ($py -and $rt -and $wt)) { Write-Host "layer  off: run layer\fetch_runtime.ps1 once (python=$([bool]$py) runtime=$rt wasmtime=$wt)"; $Layer = $false }
}
$ListenHost = '0.0.0.0'; $ListenPort = $Port; $LayerProc = $null
if ($Layer) {
    $InnerPort = $Port + 10000; $ListenHost = '127.0.0.1'; $ListenPort = $InnerPort
    $env:BONSAI_LAYER_KEY = $ApiKey
    # G1b (DECISIONS 2026-10-08): the example check is on for the 2B (HumanEval medium 86 -> 90 of 164, none broken).
    # BONSAI_EXAMPLE_CHECK=0 turns it off, =1 turns it on for any size.
    $ExampleCheck = if ($env:BONSAI_EXAMPLE_CHECK) { $env:BONSAI_EXAMPLE_CHECK -ne '0' } else { (Split-Path $Model -Leaf) -match '-2B-' }
    $LayerArgs = @(('"' + (Join-Path $LayerDir 'bonsai_layer.py') + '"'), '--host', '0.0.0.0', '--port', "$Port", '--upstream', "http://127.0.0.1:$InnerPort")
    if ($ExampleCheck) { $LayerArgs += '--example-check' }
    # S3a: edit-call repair (old text that differs from the file only in indentation). Off until a live check;
    # BONSAI_EDIT_REPAIR=1 turns it on.
    $EditRepair = $env:BONSAI_EDIT_REPAIR -eq '1'
    if ($EditRepair) { $LayerArgs += '--edit-repair' }
    $LayerProc = Start-Process python -PassThru -WindowStyle Hidden -ArgumentList $LayerArgs
    Remove-Item Env:BONSAI_LAYER_KEY
}

Write-Host "model  $(Split-Path $Model -Leaf)"
Write-Host "window $Ctx / $Ctk (all in VRAM)   ubatch $UBatch   mask=$(if ($MaskArgs) { 'packed' } else { 'f16' })"
Write-Host "listen 0.0.0.0:$Port  think=$Think effort=$Effort budget=$ThinkBudget harness-proofing=$($HarnessArgs.Count -gt 0) backend-sampling=$($BsArgs.Count -gt 0) presence=$Presence"
Write-Host "layer  $(if ($Layer) { "on: clients use :$Port; llama-server on 127.0.0.1:$ListenPort$(if ($ExampleCheck) { '; example check on' })$(if ($EditRepair) { '; edit repair on' })" } else { 'off' })"
Write-Host "api    Authorization: Bearer <artifacts/api_key.txt>"

[string[]]$ServerArgs = @() + $BudgetArgs + $HarnessArgs + $BsArgs + $MaskArgs + $TemplateArgs + $LogArgs + @(
    '-n', '24576', '-m', $Model, '-ngl', '99', '-fa', 'on', '-c', "$Ctx", '-np', '1', '-b', '2048', '-ub', "$UBatch",
    '-ctk', $Ctk, '-ctv', $Ctk, '--host', $ListenHost, '--port', "$ListenPort", '--alias', 'bonsai-2-small', '--jinja',
    '--prio', '2', '--poll', '100', '--metrics', '--api-key', $ApiKey,
    '--temp', '1.0', '--top-p', '0.95', '--top-k', '20', '--presence-penalty', "$Presence")
$StdErrFile = if ($env:BONSAI_STDERR_FILE) { if ([IO.Path]::IsPathRooted($env:BONSAI_STDERR_FILE)) { $env:BONSAI_STDERR_FILE } else { Join-Path $Root $env:BONSAI_STDERR_FILE } } else { $null }
Set-Location $Bin
try {
    if ($StdErrFile) {
        New-Item -ItemType Directory -Force (Split-Path $StdErrFile) | Out-Null
        $Quoted = $ServerArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }
        $CmdLine = '"' + $Server + '" ' + ($Quoted -join ' ') + ' 2>> "' + $StdErrFile + '"'
        Add-Content -Path $StdErrFile -Value ("=== {0:yyyy-MM-dd HH:mm:ss} start: {1}" -f (Get-Date), (($Quoted -join ' ') -replace $ApiKey, '<key>'))
        $Proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/s', '/c', ('"' + $CmdLine + '"')) -WorkingDirectory $Bin -NoNewWindow -Wait -PassThru
    } else {
        & .\llama-server.exe @ServerArgs
    }
} finally {
    if ($LayerProc -and -not $LayerProc.HasExited) { Stop-Process -Id $LayerProc.Id -Force -ErrorAction SilentlyContinue }
}
