$ErrorActionPreference = 'Stop'
$Cuda = 'C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13'
$Dump = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe'
$Lib  = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\lib.exe'
$Out  = Join-Path $Cuda 'lib\x64'
New-Item -ItemType Directory -Force -Path $Out | Out-Null

function New-ImportLib([string]$Dll, [string]$ImplibName) {
    $tmp = Join-Path $env:TEMP ($ImplibName + '.exports.txt')
    $def = Join-Path $env:TEMP ($ImplibName + '.def')
    & $Dump /exports $Dll > $tmp
    $names = @()
    Get-Content $tmp | ForEach-Object {
        if ($_ -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)$') {
            $names += $Matches[1]
        }
    }
    if ($names.Count -lt 10) { throw "too few exports from $Dll : $($names.Count)" }
    $libname = [IO.Path]::GetFileNameWithoutExtension($Dll)
    $lines = @("LIBRARY $libname", 'EXPORTS') + $names
    Set-Content -Path $def -Value $lines -Encoding ASCII
    $implib = Join-Path $Out $ImplibName
    & $Lib /nologo /machine:x64 /def:$def /out:$implib
    if ($LASTEXITCODE -ne 0) { throw "lib failed for $Dll" }
    Write-Host "wrote $implib exports=$($names.Count)"
}

New-ImportLib (Join-Path $Cuda 'bin\x86_64\cublas64_13.dll') 'cublas.lib'
New-ImportLib (Join-Path $Cuda 'bin\x86_64\cublasLt64_13.dll') 'cublasLt.lib'

# CMake FindCUDAToolkit wants these exact names plus the DLLs on PATH.
Copy-Item (Join-Path $Cuda 'bin\x86_64\cublas64_13.dll') (Join-Path $Cuda 'bin\cublas64_13.dll') -Force
Copy-Item (Join-Path $Cuda 'bin\x86_64\cublasLt64_13.dll') (Join-Path $Cuda 'bin\cublasLt64_13.dll') -Force
Copy-Item (Join-Path $Cuda 'bin\x86_64\cudart64_13.dll') (Join-Path $Cuda 'bin\cudart64_13.dll') -Force
Get-ChildItem $Out -Filter 'cublas*.lib' | Select-Object Name, Length
