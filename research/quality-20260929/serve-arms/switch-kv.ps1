param([Parameter(Mandatory)][ValidateSet('q8_0', 'f16')][string]$Kv)
$ErrorActionPreference = 'Stop'
$Key = (Get-Content 'C:\Users\pwall\Projects\bonsai-2-27b-serve\artifacts\api_key.txt' -Raw).Trim()
$H = @{ Authorization = "Bearer $Key" }
try { if (@(Invoke-RestMethod http://127.0.0.1:8080/slots -Headers $H | Where-Object { $_.is_processing }).Count) { throw 'busy' } } catch { if ("$_" -eq 'busy') { throw } }
Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
Start-Process powershell -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'run-kv.ps1'),'-Kv',$Kv) | Out-Null
for ($i = 0; $i -lt 100; $i++) { Start-Sleep 3; try { if ((Invoke-RestMethod http://127.0.0.1:8080/health -TimeoutSec 3).status -eq 'ok') { break } } catch {} }
$c = (Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'").CommandLine.Replace($Key, '<REDACTED>')
"cmd $c"
nvidia-smi --query-gpu=memory.used --format=csv,noheader
