# Detached final receipt run: depth sweep + Killy suite against the running :8080 serve. Log: run_final_20260927.log
$S = "C:\Users\pwall\AppData\Local\Temp\claude\C--\127dae63-30bf-4770-81eb-deb0b7002508\scratchpad"
$R = "C:\Users\pwall\Projects\bonsai-2-27b-serve"
$env:KEY = [IO.File]::ReadAllText("$R\artifacts\api_key.txt").Trim(); $env:PORT = "8080"
$env:DEPTHS = "4096,16384,32768,65536,112000,131072,180000,258000"; $env:NGEN = "256"
"== depth sweep (final recipe, iGPU display, margin 1000)  $(Get-Date -Format s)"
python "$S\depthbench.py" 2>&1 | Tee-Object "$R\artifacts\eval\final_sweep_20260927.txt"
"== killy suite  $(Get-Date -Format s)"
Set-Location $R
& "$R\bench\killy_suite.ps1" -Tag 20260927 2>&1
"== done  $(Get-Date -Format s)"
