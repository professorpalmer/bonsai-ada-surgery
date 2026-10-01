# Temporary: pinned A arguments on the reasoning-cache build (bin-rc770906f) with --reasoning-cache 256.
# Functional check only; restore with switch.ps1 -Arm A.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'arms.ps1')
$Key = (Get-Content -Path (Join-Path $Root 'artifacts\api_key.txt') -Raw).Trim()
[string[]]$A = (Get-ArmArgs 'A' $Key) + @('--reasoning-cache', '256')
foreach ($k in $ArmEnv.Keys) { Set-Item -Path "env:$k" -Value $ArmEnv[$k] }
Set-Location (Join-Path $Root 'bin-rc770906f')
& .\llama-server.exe @A
