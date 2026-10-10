# Issue #16: one CSV line per second: time, llama-server private bytes (MiB, all servers), system commit (GiB),
# free physical memory (GiB). Stops when the file named by -StopFile exists.
#   powershell -File bench\ram_sample.ps1 -Out logs\ram_A.csv -StopFile logs\ram.stop
param([string]$Out, [string]$StopFile)
"time,server_private_mib,commit_gib,free_phys_gib" | Set-Content -Encoding ascii $Out
while (-not (Test-Path $StopFile)) {
    $priv = 0
    foreach ($p in (Get-Process llama-server -ErrorAction SilentlyContinue)) { $priv += $p.PrivateMemorySize64 }
    $os = Get-CimInstance Win32_OperatingSystem
    $commit = ($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1MB
    $free = $os.FreePhysicalMemory / 1MB
    "{0},{1},{2},{3}" -f (Get-Date -Format 'HH:mm:ss'), [int]($priv / 1MB), [math]::Round($commit, 2), [math]::Round($free, 2) | Add-Content -Encoding ascii $Out
    Start-Sleep -Seconds 1
}
