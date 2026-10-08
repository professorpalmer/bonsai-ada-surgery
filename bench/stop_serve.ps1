# Stops every serve that holds the serve ports (8080 layer or server, 18080 inner server), by PID, together with the
# launcher console that started it (a start-server.ps1). Bench scripts call this before each arm, so that a serve
# left by an earlier step (for example a bundle smoke that restores the product serve) cannot answer for the arm.
#   powershell -File bench\stop_serve.ps1 [-Ports 8080,18080]
param([int[]]$Ports = @(8080, 18080))
$ids = @(Get-NetTCPConnection -LocalPort $Ports -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
$ids += @(Get-Process llama-server -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$stop = @()
foreach ($id in ($ids | Sort-Object -Unique)) {
    $stop += $id
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
    for ($n = 0; $p -and $n -lt 3; $n++) {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" -ErrorAction SilentlyContinue
        if ($p -and $p.CommandLine -match 'start-server\.ps1') { $stop += $p.ProcessId; break }
        if (-not $p -or $p.Name -notmatch '^(cmd|powershell)\.exe$') { break }
        if ($p.Name -eq 'cmd.exe') { $stop += $p.ProcessId }
    }
}
foreach ($id in ($stop | Sort-Object -Unique)) {
    try { Stop-Process -Id $id -Force -ErrorAction Stop; "stopped $id" } catch { }
}
if ($stop) { Start-Sleep 5 }
