param(
    [int]$Seconds = 20,
    [string]$OutFile = 'C:\Users\pwall\Projects\bonsai-2-27b-serve\artifacts\gpu_sample.csv'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
'ts,pstate,gr_mhz,mem_mhz,power_w,util_gpu,util_mem,vram_mib,temp_c' | Set-Content -Path $OutFile
$end = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $end) {
    $row = nvidia-smi --query-gpu=pstate,clocks.gr,clocks.mem,power.draw,utilization.gpu,utilization.memory,memory.used,temperature.gpu --format=csv,noheader,nounits
    $line = '{0},{1}' -f (Get-Date).ToString('o'), ($row -replace '\s+', '')
    Add-Content -Path $OutFile -Value $line
    Start-Sleep -Milliseconds 200
}
