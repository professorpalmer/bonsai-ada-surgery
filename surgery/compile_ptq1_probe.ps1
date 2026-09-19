$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Cuda = 'C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13'
$Vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
$Src = Join-Path $PSScriptRoot 'ptq1_lut_kernel.cu'
$Out = Join-Path $PSScriptRoot 'ptq1_lut_kernel.exe'

$cmd = @"
call `"$Vcvars`"
set CUDA_PATH=$Cuda
set PATH=$Cuda\bin;$Cuda\nvvm\bin;%PATH%
nvcc -O3 -std=c++17 -arch=sm_89 --use_fast_math -I `"$Cuda\include`" -L `"$Cuda\lib\x64`" -lcudart -o `"$Out`" `"$Src`"
"@
$bat = Join-Path $env:TEMP 'compile_ptq1_probe.bat'
Set-Content -Path $bat -Value $cmd -Encoding ASCII
cmd /c $bat
if ($LASTEXITCODE -ne 0) { throw "nvcc failed $LASTEXITCODE" }
& $Out
if ($LASTEXITCODE -ne 0) { throw "probe failed $LASTEXITCODE" }
