$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Src  = Join-Path $Root 'vendor\prism-llama'
$Build = Join-Path $Root 'tooling\build-ada'
$Cuda = 'C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13'
$Vcvars = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
$Cmake = 'C:\Users\pwall\AppData\Local\Programs\Python\Python312\Scripts\cmake.exe'
New-Item -ItemType Directory -Force -Path $Build | Out-Null

$cmd = @"
call `"$Vcvars`"
set CUDA_PATH=$Cuda
set CUDAToolkit_ROOT=$Cuda
set PATH=$Cuda\bin;$Cuda\bin\x86_64;$Cuda\nvvm\bin;%PATH%
`"$Cmake`" -S `"$Src`" -B `"$Build`" -G "Visual Studio 17 2022" -A x64 -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89-real -DGGML_CUDA_GRAPHS=ON -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_CURL=OFF -DGGML_RPC=OFF -DGGML_BLAS=OFF -DGGML_NATIVE=OFF -DGGML_CCACHE=OFF -DCMAKE_CUDA_COMPILER=`"$Cuda\bin\nvcc.exe`" -DCUDAToolkit_ROOT=`"$Cuda`"
if errorlevel 1 exit /b 1
`"$Cmake`" --build `"$Build`" --config Release --target llama-server llama-bench -j
"@
$bat = Join-Path $Root 'tooling\build_ada_server.bat'
Set-Content -Path $bat -Value $cmd -Encoding ASCII
cmd /c $bat
if ($LASTEXITCODE -ne 0) { throw "build failed $LASTEXITCODE" }
Write-Host "built $Build"
