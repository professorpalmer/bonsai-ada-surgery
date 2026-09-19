# Pin the 4070 to driver-max SM and GDDR clocks. Needs UAC.
$ErrorActionPreference = 'Stop'
$arg = '-lgc 3105,3105 -lmc 10501,10501 -pl 200'
$p = Start-Process -FilePath 'nvidia-smi.exe' -ArgumentList $arg -Verb RunAs -Wait -PassThru
Write-Host "elevate exit $($p.ExitCode)"
nvidia-smi --query-gpu=clocks.gr,clocks.sm,clocks.mem,clocks.max.gr,clocks.max.mem,power.limit,pstate --format=csv
