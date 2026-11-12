# One server, one greedy request, stop by PID. For load / acceptance checks.
# one_shot.ps1 -Tag t -Draft <gguf or ''> -NMax 7 -Extra '...' -Prompt '...'
param([string]$Tag, [string]$Model = '<repo>/models\Ternary-Bonsai-2-27B-PTQ1_0.gguf',
      [string]$Draft = '', [int]$NMax = 7, [string]$SpecType = 'draft-dflash', [string]$Extra = '',
      [string]$Prompt = 'Write a Python function that returns the n-th Fibonacci number, with a docstring and two doctests.',
      [int]$Tokens = 200, [int]$Ctx = 8192)
$Bin = '<engine-bin>'
$LogDir = '<draft-dir>\logs'
New-Item -ItemType Directory -Force $LogDir | Out-Null
$env:GGML_CUDA_BATCH_INVARIANT = '1'
$env:LLAMA_ARG_LOG_VERBOSITY = '4'
$a = @('-m', $Model, '-ngl', '99', '-fa', 'on', '-c', "$Ctx", '-np', '1', '-ctk', 'q8_0', '-ctv', 'q8_0', '--jinja', '--fit', 'off',
       '--host', '127.0.0.1', '--port', '8897')
if ($Draft) { $a += @('-md', $Draft, '-ngld', '99', '--spec-type', $SpecType, '--spec-draft-n-max', "$NMax", '-ctkd', 'q8_0', '-ctvd', 'q8_0') }
if ($Extra) { $a += ($Extra -split '\s+' | Where-Object { $_ }) }
$p = Start-Process -FilePath "$Bin\llama-server.exe" -ArgumentList $a -WorkingDirectory $Bin -WindowStyle Hidden `
     -RedirectStandardOutput "$LogDir\$Tag.out" -RedirectStandardError "$LogDir\$Tag.err" -PassThru
$ok = $false
for ($i = 0; $i -lt 240; $i++) {
    Start-Sleep 1
    try { if ((Invoke-RestMethod -TimeoutSec 3 http://127.0.0.1:8897/health).status -eq 'ok') { $ok = $true; break } } catch { }
    if ($p.HasExited) { break }
}
if ($ok) {
    $mem = (& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits).Trim()
    $body = @{ messages = @(@{ role = 'user'; content = $Prompt }); max_tokens = $Tokens; temperature = 0; top_k = 1;
               chat_template_kwargs = @{ enable_thinking = $false } } | ConvertTo-Json -Depth 5
    try {
        $r = Invoke-RestMethod -TimeoutSec 900 -Method Post -ContentType 'application/json' -Body $body http://127.0.0.1:8897/v1/chat/completions
        $t = $r.timings
        Write-Output ("{0} mem={1} decode={2:N1} prefill={3:N1} draft={4} acc={5} n={6}" -f $Tag, $mem, $t.predicted_per_second, $t.prompt_per_second, $t.draft_n, $t.draft_n_accepted, $t.predicted_n)
        Write-Output ($r.choices[0].message.content.Substring(0, [Math]::Min(300, $r.choices[0].message.content.Length)))
    } catch { Write-Output "$Tag request failed: $_" }
} else { Write-Output "$Tag server did not start (exited=$($p.HasExited))" }
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 30; $i++) { Start-Sleep 1; if (-not (Get-Process llama-server -ErrorAction SilentlyContinue)) { break } }
$left = @(Get-Process llama-server -ErrorAction SilentlyContinue).Count
Write-Output ("{0} stopped; llama-server left={1}; mem={2}" -f $Tag, $left, (& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits).Trim())
