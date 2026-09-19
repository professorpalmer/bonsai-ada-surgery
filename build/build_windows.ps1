# Build the patched PrismML llama.cpp (llama-server + llama-bench, CUDA) on Windows without
# installing the CUDA toolkit: VS Build Tools + NVIDIA's pip wheels are enough.
#
#   python -m pip install cmake ninja nvidia-cuda-nvcc nvidia-cuda-runtime nvidia-cublas nvidia-cuda-nvrtc
#   .\build\build_windows.ps1                 # arch auto-detected from nvidia-smi (e.g. 89 for Ada)
#   .\build\build_windows.ps1 -Arch 86        # RTX 30xx
#   .\build\build_windows.ps1 -Arch "86;89"   # several
#
# Output: .\bin\llama-server.exe, .\bin\llama-bench.exe plus the DLLs they need.
# If an official CUDA toolkit is installed (CUDA_PATH set, bin\nvcc.exe present) it is used instead.
param(
    [string] $Arch = "",
    [string] $Src = "",
    [string] $Build = "",
    [string] $Out = "",
    [switch] $Tests
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Src)   { $Src = Join-Path $Root 'vendor\prism-llama' }
if (-not $Build) { $Build = Join-Path $Root 'tooling\build' }
if (-not $Out)   { $Out = Join-Path $Root 'bin' }
if (-not (Test-Path (Join-Path $Src 'CMakeLists.txt'))) {
    throw "no llama.cpp source at $Src - clone professorpalmer/llama.cpp-ada-ternary (branch ada-ptq1-surgery) there, or apply patches\*.patch to PrismML-Eng/llama.cpp"
}

# GPU arch
if (-not $Arch) {
    $cc = (& nvidia-smi --query-gpu=compute_cap --format=csv,noheader | Select-Object -First 1).Trim()
    if (-not $cc) { throw 'nvidia-smi not found; pass -Arch' }
    $Arch = $cc.Replace('.', '')
}
$ArchList = ($Arch -split '[;,]' | ForEach-Object { "$($_.Trim())-real" }) -join ';'

# Visual Studio (Build Tools or full)
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'Visual Studio Build Tools 2022 (C++ workload) not found' }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat missing under $vs" }

# CUDA: official toolkit if present, else the pip wheel tree
$Cuda = $env:CUDA_PATH
if (-not ($Cuda -and (Test-Path (Join-Path $Cuda 'bin\nvcc.exe')))) {
    $sp = & python -c "import site; print(site.getsitepackages()[0])"
    $Cuda = Join-Path $sp 'nvidia\cu13'
    if (-not (Test-Path (Join-Path $Cuda 'bin\nvcc.exe'))) {
        throw 'no CUDA compiler: install the toolkit or `python -m pip install nvidia-cuda-nvcc nvidia-cuda-runtime nvidia-cublas nvidia-cuda-nvrtc`'
    }
    $pip = $true
} else { $pip = $false }

# cmake / ninja: PATH first, then pip's Scripts dir
function Find-Tool([string]$name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $scripts = & python -c "import sysconfig; print(sysconfig.get_path('scripts'))"
    $p = Join-Path $scripts "$name.exe"
    if (Test-Path $p) { return $p }
    throw "$name not found; python -m pip install $name"
}
$cmake = Find-Tool cmake
$ninja = Find-Tool ninja

New-Item -ItemType Directory -Force -Path $Build, $Out | Out-Null
$targets = 'llama-server llama-bench'
$testFlag = 'OFF'
if ($Tests) { $targets += ' test-backend-ops'; $testFlag = 'ON' }

$implibs = ''
if ($pip) {
    # The wheels ship DLLs but no import libraries; FindCUDAToolkit needs lib\x64\{cublas,cublasLt}.lib
    # and the DLLs under bin\. Generate them from the DLL export tables with dumpbin + lib.
    $implibs = @"
if not exist "$Cuda\lib\x64" mkdir "$Cuda\lib\x64"
for %%D in (cublas64_13 cublasLt64_13 cudart64_13) do (
  if exist "$Cuda\bin\x86_64\%%D.dll" if not exist "$Cuda\bin\%%D.dll" copy /y "$Cuda\bin\x86_64\%%D.dll" "$Cuda\bin\" >nul
)
if not exist "$Cuda\lib\x64\cublas.lib"   powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\make_import_lib.ps1" "$Cuda\bin\cublas64_13.dll"   "$Cuda\lib\x64\cublas.lib"
if not exist "$Cuda\lib\x64\cublasLt.lib" powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\make_import_lib.ps1" "$Cuda\bin\cublasLt64_13.dll" "$Cuda\lib\x64\cublasLt.lib"
if not exist "$Cuda\lib\x64\cudart.lib"   powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\make_import_lib.ps1" "$Cuda\bin\cudart64_13.dll"   "$Cuda\lib\x64\cudart.lib"
"@
}

$bat = Join-Path $Build 'build.bat'
@"
@echo off
call "$vcvars" >nul
set CUDA_PATH=$Cuda
set CUDAToolkit_ROOT=$Cuda
set PATH=$Cuda\bin;$Cuda\bin\x86_64;$Cuda\nvvm\bin;%PATH%
$implibs
"$cmake" -S "$Src" -B "$Build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MAKE_PROGRAM="$ninja" -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="$ArchList" -DGGML_CUDA_GRAPHS=ON -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_TESTS=$testFlag -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_CURL=OFF -DGGML_RPC=OFF -DGGML_BLAS=OFF -DGGML_NATIVE=OFF -DGGML_CCACHE=OFF -DCMAKE_CUDA_COMPILER="$Cuda\bin\nvcc.exe" -DCUDAToolkit_ROOT="$Cuda"
if errorlevel 1 exit /b 1
"$cmake" --build "$Build" --target $targets -j
if errorlevel 1 exit /b 1
"@ | Set-Content -Path $bat -Encoding ASCII

Write-Host "arch=$ArchList cuda=$Cuda ($(if ($pip) {'pip wheels'} else {'toolkit'}))"
cmd /c $bat
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }

# Stage runnable tree
Copy-Item (Join-Path $Build 'bin\*.exe') $Out -Force
Copy-Item (Join-Path $Build 'bin\*.dll') $Out -Force
foreach ($d in 'cudart64_13.dll', 'cublas64_13.dll', 'cublasLt64_13.dll', 'nvJitLink_130_0.dll', 'nvvm64_40_0.dll') {
    $f = Get-ChildItem $Cuda -Recurse -Filter $d -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { Copy-Item $f.FullName $Out -Force }
}
Write-Host "staged $Out"
