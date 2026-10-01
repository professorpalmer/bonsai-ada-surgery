# Runs one arm in the foreground (the window that owns the server, like start-server.ps1).
#   powershell -NoExit -NoProfile -ExecutionPolicy Bypass -File run-arm.ps1 -Arm A|B
# -DryRun prints the sanitized command and exits without starting anything.
param([Parameter(Mandatory)][ValidateSet('A', 'B')][string]$Arm, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'arms.ps1')
$Key = (Get-Content -Path (Join-Path $Root 'artifacts\api_key.txt') -Raw).Trim()
[string[]]$A = Get-ArmArgs $Arm $Key
$Shown = ($A -join ' ').Replace($Key, '<REDACTED>')
if ($DryRun) { $Shown; return }
foreach ($k in $ArmEnv.Keys) { Set-Item -Path "env:$k" -Value $ArmEnv[$k] }
Write-Host "arm $Arm  $Shown"
Set-Location $Bin
& .\llama-server.exe @A
