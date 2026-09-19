# Build a CUDAToolkit-shaped tree from NVIDIA's Windows pip wheels.
# No admin, no official toolkit installer. FindCUDAToolkit just needs
# bin/nvcc.exe, include/cuda.h, lib/x64/{cudart,cublas,cublasLt}.lib.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Dst  = Join-Path $Root 'tooling\cuda-pip'
New-Item -ItemType Directory -Force -Path $Dst, "$Dst\bin", "$Dst\include", "$Dst\lib\x64", "$Dst\nvvm\bin", "$Dst\nvvm\libdevice" | Out-Null

$sp = python -c "import site; print(site.getsitepackages()[0])"
if (-not $sp) { throw 'no site-packages' }
$nvidia = Join-Path $sp 'nvidia'

function Link-Tree([string]$Src, [string]$Into) {
    if (-not (Test-Path $Src)) { return 0 }
    $n = 0
    Get-ChildItem $Src -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($Src.Length).TrimStart('\')
        $dest = Join-Path $Into $rel
        $dir = Split-Path $dest -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if (Test-Path $dest) { Remove-Item $dest -Force }
        New-Item -ItemType HardLink -Path $dest -Target $_.FullName | Out-Null
        $n++
    }
    return $n
}

$copied = 0
$copied += Link-Tree (Join-Path $nvidia 'cuda_nvcc\bin') "$Dst\bin"
$copied += Link-Tree (Join-Path $nvidia 'cuda_nvcc\nvvm') "$Dst\nvvm"
$copied += Link-Tree (Join-Path $nvidia 'cuda_crt\include') "$Dst\include"
$copied += Link-Tree (Join-Path $nvidia 'cuda_runtime\include') "$Dst\include"
$copied += Link-Tree (Join-Path $nvidia 'cuda_cccl\include') "$Dst\include"
$copied += Link-Tree (Join-Path $nvidia 'nvvm') "$Dst\nvvm"
$copied += Link-Tree (Join-Path $nvidia 'cuda_nvvm') "$Dst\nvvm"

# libs live under nvidia/<pkg>/lib or bin
foreach ($pkg in @('cuda_runtime','cublas','nvjitlink','cuda_nvrtc')) {
    $lib = Join-Path $nvidia "$pkg\lib"
    $bin = Join-Path $nvidia "$pkg\bin"
    if (Test-Path $lib) { $copied += Link-Tree $lib "$Dst\lib\x64" }
    if (Test-Path $bin) {
        $copied += Link-Tree $bin "$Dst\bin"
        # import libs sometimes sit next to the DLLs
        Get-ChildItem $bin -Filter '*.lib' -ErrorAction SilentlyContinue | ForEach-Object {
            $dest = Join-Path "$Dst\lib\x64" $_.Name
            if (Test-Path $dest) { Remove-Item $dest -Force }
            New-Item -ItemType HardLink -Path $dest -Target $_.FullName | Out-Null
            $copied++
        }
    }
}

# nvcc on wheels often wants NVVM64_*.dll next to itself
Get-ChildItem $nvidia -Recurse -Include 'nvcc.exe','cicc.exe','ptxas.exe','cuda.h','cudart.lib','cublas.lib','cublasLt.lib','libdevice.10.bc' -ErrorAction SilentlyContinue |
    Select-Object -First 40 FullName | ForEach-Object { $_.FullName }

Write-Host "linked=$copied dst=$Dst"
Get-ChildItem "$Dst\bin" -ErrorAction SilentlyContinue | Select-Object Name
Get-ChildItem "$Dst\include\cuda.h","$Dst\lib\x64\cudart.lib","$Dst\lib\x64\cublas.lib" -ErrorAction SilentlyContinue | Select-Object FullName, Length
