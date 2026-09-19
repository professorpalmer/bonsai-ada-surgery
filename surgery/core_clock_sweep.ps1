# Sweep locked SM clocks (nvidia-smi -lgc) and bench TG at each; single UAC prompt.
# Results append to artifacts\core_sweep.txt. Resets to default clocks at the end.
param([string] $Clocks = "2100,2400,2600,2805")

$root = "C:\Users\pwall\Projects\bonsai-2-27b-serve"
$log = Join-Path $root "artifacts\core_sweep.txt"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Clocks `"$Clocks`""
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $args -PassThru
    $p.WaitForExit()
    "elevated exit code: $($p.ExitCode)"
    if (Test-Path $log) { Get-Content $log -Tail 8 }
    exit 0
}

try {
    Add-Content $log ("--- " + (Get-Date -Format s) + " mem=" + (nvidia-smi --query-gpu=clocks.mem --format=csv,noheader))
    foreach ($c in ($Clocks -split ",")) {
        $c = $c.Trim()
        $r = nvidia-smi -lgc "$c,$c" 2>&1 | Out-String
        Start-Sleep -Seconds 2
        $res = & python (Join-Path $root "surgery\bench_with_smi.py") "core_$c" 2>&1 | Out-String
        Add-Content $log ("lgc $c : " + (($res -split "`n" | Where-Object { $_ -match "^tg|samples=" }) -join "  ||  ") + "  [" + $r.Trim() + "]")
    }
    nvidia-smi -rgc | Out-Null
    Add-Content $log "reset to default clocks"
} catch {
    Add-Content $log ("ERROR: " + $_.Exception.Message + " " + $_.ScriptStackTrace)
    nvidia-smi -rgc | Out-Null
    exit 1
}
