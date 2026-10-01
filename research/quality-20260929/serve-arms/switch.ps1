# Switch the live server to arm A or B (also the rollback: -Arm A). Run only when Cary relays the switch.
#   powershell -NoProfile -ExecutionPolicy Bypass -File switch.ps1 -Arm B
# Refuses if the slot is busy. Stops the running llama-server, starts the arm in a new visible window,
# waits for /health, then prints a receipt (no key). If B fails readiness it restores A automatically.
param([Parameter(Mandatory)][ValidateSet('A', 'B')][string]$Arm, [int]$TimeoutSec = 300)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'arms.ps1')
$Key = (Get-Content -Path (Join-Path $Root 'artifacts\api_key.txt') -Raw).Trim()
$H = @{ Authorization = "Bearer $Key" }
$Base = 'http://127.0.0.1:8080'

function Get-Slots { Invoke-RestMethod -Uri "$Base/slots" -Headers $H -TimeoutSec 5 }
function Start-Arm([string]$Which) {
    $p = Start-Process powershell -PassThru -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'run-arm.ps1'), '-Arm', $Which)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        try { if ((Invoke-RestMethod -Uri "$Base/health" -TimeoutSec 3).status -eq 'ok') { return $true } } catch {}
    }
    return $false
}
function Stop-Server {
    Get-Process llama-server -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    for ($i = 0; $i -lt 30 -and (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue); $i++) { Start-Sleep 1 }
}
function Write-Receipt {
    $srv = Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'"
    $props = Invoke-RestMethod -Uri "$Base/props" -Headers $H
    $slots = Get-Slots
    $tsha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash(
        [Text.Encoding]::UTF8.GetBytes($props.chat_template))).Replace('-', '').ToLower()
    "pid          $($srv.ProcessId)  started $($srv.CreationDate)"
    "cmd          $($srv.CommandLine.Replace($Key, '<REDACTED>'))"
    "build        $($props.build_info)"
    "model        $($props.model_alias)  $($props.model_path)"
    "template     $tsha"
    "slots        $(@($slots).Count)  n_ctx $($slots[0].n_ctx)  speculative $($slots[0].speculative)  processing $($slots[0].is_processing)"
    "env          $(& python -c "import psutil; e=psutil.Process($($srv.ProcessId)).environ(); print('GGML_CUDA_BATCH_INVARIANT=' + str(e.get('GGML_CUDA_BATCH_INVARIANT')))")"
}

try { $busy = @(Get-Slots | Where-Object { $_.is_processing }).Count } catch { $busy = 0 }
if ($busy -gt 0) { throw 'slot is processing a request: not switching' }

Stop-Server
if (Start-Arm $Arm) { Write-Receipt; return }
Write-Warning "arm $Arm failed readiness within $TimeoutSec s"
if ($Arm -ne 'A') {
    Stop-Server
    if (Start-Arm 'A') { 'RESTORED A'; Write-Receipt } else { throw 'A also failed readiness: server is DOWN' }
}
