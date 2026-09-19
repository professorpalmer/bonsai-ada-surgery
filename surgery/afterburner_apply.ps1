# Write MSI Afterburner overclock profiles for the RTX 4070 and apply one of them.
# Afterburner and its Profiles dir live under Program Files, so this self-elevates (one UAC prompt).
#
#   .\afterburner_apply.ps1 -Profile 2          # apply profile 2 (see table below)
#   .\afterburner_apply.ps1 -Profile 5          # profile 5 = everything back to stock
#
# Profile  mem offset  core offset
#   1        +500 MHz      0
#   2       +1000 MHz      0
#   3       +1300 MHz      0
#   4       +1500 MHz      0
#   5           0          0   (stock)
#   6       +1750 MHz      0
#   7       +2000 MHz      0
#   8       +1600 MHz      0
# Offsets are stored in kHz in the Afterburner cfg. GDDR6X has EDR (error detect + replay), so an
# offset that is too high shows up as lower throughput, not corruption; verify with a greedy A/B.
param(
    [Parameter(Mandatory = $true)][int] $Profile
)

$ab = "C:\Program Files (x86)\MSI Afterburner"
$exe = Join-Path $ab "MSIAfterburner.exe"
$cfg = Join-Path $ab "Profiles\VEN_10DE&DEV_2786&SUBSYS_51381462&REV_A1&BUS_1&DEV_0&FN_0.cfg"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Profile $Profile"
    # No -Wait: it would also wait on the Afterburner descendant that stays resident in the tray.
    $before = (Get-Process MSIAfterburner -ErrorAction SilentlyContinue | Select-Object -First 1).Id
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args
    foreach ($i in 1..120) {
        Start-Sleep -Seconds 1
        $now = (Get-Process MSIAfterburner -ErrorAction SilentlyContinue | Select-Object -First 1).Id
        if ($now -and $now -ne $before) { Start-Sleep -Seconds 6; break }
    }
    exit 0
}

$mem = @{ 1 = 500000; 2 = 1000000; 3 = 1300000; 4 = 1500000; 5 = 0; 6 = 1750000; 7 = 2000000; 8 = 1600000 }
$lines = @("[Startup]", "Format=2", "")
foreach ($p in 1..8) {
    $lines += "[Profile$p]"
    $lines += "Format=2"
    $lines += "PowerLimit=100"
    $lines += "ThermalLimit=83"
    $lines += "ThermalPrioritize=0"
    $lines += "CoreClkBoost=0"
    $lines += "MemClkBoost=$($mem[$p])"
    $lines += "CoreVoltageBoost=0"
    $lines += ""
}
Set-Content -Path $cfg -Value $lines -Encoding ASCII

Get-Process MSIAfterburner -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800
Start-Process $exe -ArgumentList "-Profile$Profile"
Start-Sleep -Seconds 6
