# Control for the harness-proofing receipts: the same server recipe with BONSAI_HARNESS_PROOF=0 on :8091, the two app
# arms on the first 20 HumanEval problems. Then the normal serve comes back on :8080.
$R = "C:\Users\pwall\Projects\bonsai-2-27b-serve"
Set-Location $R
Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'start-server' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep 3
$env:BONSAI_PORT = "8091"; $env:BONSAI_HARNESS_PROOF = "0"
$p = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File $R\start-server.ps1" -RedirectStandardOutput "$R\artifacts\eval\control_server.out" -RedirectStandardError "$R\artifacts\eval\control_server.err" -PassThru -WindowStyle Hidden
for ($i = 0; $i -lt 120; $i++) { Start-Sleep 2; try { if ((Invoke-WebRequest http://127.0.0.1:8091/health -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break } } catch {} }
"== control: harness-proofing OFF  $(Get-Date -Format s)"
python bench\humaneval_run.py --base http://127.0.0.1:8091 --arm app --effort high --temp -1 --max-tokens 256 --limit 20 --out artifacts\eval\killy_20260927\control-app-high 2>&1 | Select-String 'pass@1|error' | ForEach-Object { $_.Line }
python bench\humaneval_run.py --base http://127.0.0.1:8091 --arm app --temp -1 --max-tokens 4096 --limit 20 --out artifacts\eval\killy_20260927\control-app-4096 2>&1 | Select-String 'pass@1|error' | ForEach-Object { $_.Line }
Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'start-server' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep 3
Remove-Item Env:BONSAI_PORT, Env:BONSAI_HARNESS_PROOF -ErrorAction SilentlyContinue
Start-Process powershell -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$R\start-server.ps1`"" -WorkingDirectory $R
for ($i = 0; $i -lt 120; $i++) { Start-Sleep 2; try { if ((Invoke-WebRequest http://127.0.0.1:8080/health -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break } } catch {} }
"== serve back on :8080  $(Get-Date -Format s)"
