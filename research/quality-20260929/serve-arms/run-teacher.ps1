# Teacher reference: Qwen3.8-27B UD-Q4_K_M with Bonsai's exact chat template (same tokens in, only weights differ).
# Same binary, same sampling/reasoning controls as pinned A. Differences forced by memory: -c 32768, no MTP
# speculation, no tiered KV, GPU layers chosen by the loader's fit (the model is larger than 12 GB).
$ErrorActionPreference = 'Stop'
$Root = 'C:\Users\pwall\Projects\bonsai-2-27b-serve'
$Key = (Get-Content -Path (Join-Path $Root 'artifacts\api_key.txt') -Raw).Trim()
$env:GGML_CUDA_BATCH_INVARIANT = '1'
Set-Location (Join-Path $Root 'bin')
& .\llama-server.exe -m (Join-Path $Root 'models\donor\Qwen3.8-27B-UD-Q4_K_M.gguf') `
    --chat-template-file (Join-Path $PSScriptRoot 'bonsai-template.jinja') --jinja `
    --reasoning-budget-message "Now produce the complete answer." --reasoning-budget 20480 -n 24576 `
    --reasoning-effort-allow medium --reasoning-effort-fallback medium --reasoning-max-tokens-floor 24576 `
    --chat-template-kwargs '{\"reasoning_effort\":\"medium\"}' `
    -fa on -c 32768 -np 1 -b 2048 -ub 512 -ctk q8_0 -ctv q8_0 `
    --host 0.0.0.0 --port 8080 --alias bonsai-2-27b --prio 2 --poll 100 --metrics --api-key $Key `
    --temp 1.0 --top-p 0.95 --top-k 20
