# Official PrismML Windows CUDA release, official PTQ1_0 file, no MTP graft.
# Stock llama-server rejects the grafted *-mtp-*.gguf (Hadamard inverse on token_embd).
# Same quality recipe as start-server.ps1 (96k / q8_0, medium think, 20k budget), spec off.
# One GPU: stop the patched server before this. Default port 8081 so a leftover :8080 is obvious.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bin = Join-Path $Root 'tooling\stock-bin'
if (-not (Test-Path (Join-Path $Bin 'llama-server.exe'))) { throw "stock llama-server.exe missing in $Bin" }

$Official = Join-Path $Root 'models\Ternary-Bonsai-2-27B-PTQ1_0.gguf'
if ($env:BONSAI_MODEL) {
    $Model = if ([IO.Path]::IsPathRooted($env:BONSAI_MODEL)) { $env:BONSAI_MODEL } else { Join-Path $Root "models\$($env:BONSAI_MODEL)" }
} else {
    $Model = $Official
}
if (-not (Test-Path $Model)) { throw "stock GGUF not found: $Model" }
if ((Split-Path $Model -Leaf) -match '-mtp') {
    throw "stock cannot load a grafted MTP file. Use Ternary-Bonsai-2-27B-PTQ1_0.gguf"
}
if ((Get-Item $Model).Length -lt 5900000000) { throw "stock GGUF incomplete: $Model" }

$ApiKeyFile = Join-Path $Root 'artifacts\api_key.txt'
if (-not (Test-Path $ApiKeyFile)) { throw "api key missing: $ApiKeyFile" }
$ApiKey = (Get-Content -Path $ApiKeyFile -Raw).Trim()

$Ctx = if ($env:BONSAI_CTX) { [int]$env:BONSAI_CTX } else { 98304 }
$Ctk = if ($env:BONSAI_CTK) { $env:BONSAI_CTK } else { 'q8_0' }
$Port = if ($env:BONSAI_PORT) { [int]$env:BONSAI_PORT } else { 8081 }
$Effort = if ($env:BONSAI_EFFORT) { $env:BONSAI_EFFORT } else { 'medium' }
$Think = $env:BONSAI_THINK -ne '0'
$ThinkBudget = if ($env:BONSAI_THINK_BUDGET) { [int]$env:BONSAI_THINK_BUDGET } else { 20480 }
$ThinkBudgetMsg = if ($null -ne $env:BONSAI_THINK_BUDGET_MSG) { $env:BONSAI_THINK_BUDGET_MSG } else { 'Now produce the complete answer.' }
# PowerShell strips quotes from --chat-template-kwargs on this binary. The env form keeps them.
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = if ($Think) {
    '{"reasoning_effort":"' + $Effort + '"}'
} else {
    '{"reasoning_effort":"' + $Effort + '","enable_thinking":false}'
}

[string[]]$BsArgs = @()
if ($env:BONSAI_BS -ne '0') { $BsArgs += '--backend-sampling' }
[string[]]$BudgetMsgArgs = @()
if ($ThinkBudget -ge 0 -and $ThinkBudgetMsg) { $BudgetMsgArgs = @('--reasoning-budget-message', $ThinkBudgetMsg) }
[string[]]$ReasonArgs = if ($Think) { @('--reasoning', 'on') } else { @('--reasoning', 'off') }

Write-Host "binary tooling\stock-bin (official Prism CUDA release)"
Write-Host "model  $(Split-Path $Model -Leaf)"
Write-Host "window $Ctx / $Ctk  spec=off  think=$Think effort=$Effort budget=$ThinkBudget"
Write-Host "listen 0.0.0.0:$Port"

Set-Location $Bin
& .\llama-server.exe @BsArgs @BudgetMsgArgs @ReasonArgs `
    --reasoning-budget $ThinkBudget `
    --spec-type none `
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
