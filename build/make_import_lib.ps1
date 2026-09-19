# Generate an MSVC import library from a DLL's export table (for CUDA pip wheels, which ship no .lib).
# Must run inside a vcvars64 environment so dumpbin.exe and lib.exe are on PATH.
#   make_import_lib.ps1 <dll> <out.lib>
param(
    [Parameter(Mandatory = $true)][string] $Dll,
    [Parameter(Mandatory = $true)][string] $OutLib
)
$ErrorActionPreference = 'Stop'
$exports = & dumpbin /exports $Dll
$names = @()
foreach ($line in $exports) {
    if ($line -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)$') { $names += $Matches[1] }
}
if ($names.Count -lt 10) { throw "too few exports from $Dll ($($names.Count)); is this a vcvars shell?" }
$def = Join-Path $env:TEMP ([IO.Path]::GetFileNameWithoutExtension($OutLib) + '.def')
Set-Content -Path $def -Value (@("LIBRARY $([IO.Path]::GetFileNameWithoutExtension($Dll))", 'EXPORTS') + $names) -Encoding ASCII
New-Item -ItemType Directory -Force -Path (Split-Path $OutLib -Parent) | Out-Null
& lib /nologo /machine:x64 /def:$def /out:$OutLib
if ($LASTEXITCODE -ne 0) { throw "lib.exe failed for $Dll" }
Write-Host "wrote $OutLib ($($names.Count) exports)"
