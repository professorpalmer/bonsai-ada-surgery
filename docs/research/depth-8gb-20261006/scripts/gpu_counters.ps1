# Print the GPU process memory counters (MiB) of one process: Dedicated Usage, Shared Usage, Total Committed (P167b).
param([int]$ProcId)
$c = Get-Counter -ErrorAction SilentlyContinue "\GPU Process Memory(pid_$($ProcId)_*)\Dedicated Usage", "\GPU Process Memory(pid_$($ProcId)_*)\Shared Usage", "\GPU Process Memory(pid_$($ProcId)_*)\Total Committed"
$sum = @{}
foreach ($s in $c.CounterSamples) { $k = ($s.Path -split '\')[-1]; $sum[$k] = [math]::Round(($sum[$k] + $s.CookedValue), 0) }
"pid $ProcId : " + (($sum.Keys | Sort-Object | ForEach-Object { "$_ $([math]::Round($sum[$_] / 1MB)) MiB" }) -join ', ')
