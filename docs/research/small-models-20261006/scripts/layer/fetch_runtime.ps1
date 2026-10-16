# One-time setup for the Bonsai layer: the sandbox runtime (CPython 3.12 for WASI, VMware Labs build, zlib
# built in, checksum verified) and the wasmtime Python bindings. Then the 14 isolation canaries must pass.
$ErrorActionPreference = 'Stop'
$Dst = Join-Path $PSScriptRoot 'runtime'
$Url = 'https://github.com/vmware-labs/webassembly-language-runtimes/releases/download/python%2F3.12.0%2B20231211-040d5a6/python-3.12.0-wasi-sdk-20.0.tar.gz'
$Sha = '6c1cddbb69ae09e87eee2906bdc70539bff5f2969818a6f8457d4e6a6eb67d4d'
New-Item -ItemType Directory -Force $Dst | Out-Null
$Tar = Join-Path $Dst 'py.tar.gz'
Invoke-WebRequest -Uri $Url -OutFile $Tar
$got = (Get-FileHash $Tar -Algorithm SHA256).Hash.ToLower()
if ($got -ne $Sha) { throw "checksum mismatch: $got" }
tar -xzf $Tar -C $Dst
python -m pip install --quiet wasmtime
python (Join-Path $PSScriptRoot 'wasi-python\canaries.py')
