#!/usr/bin/env bash
# One-time setup for the Bonsai layer and the suite's sandbox on Linux/macOS: the CPython 3.12 WASI runtime
# (VMware Labs build, zlib built in, checksum verified) and the wasmtime Python bindings, then the 14 isolation
# canaries. Same files and checksum as layer/fetch_runtime.ps1.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST="$HERE/runtime"
URL='https://github.com/vmware-labs/webassembly-language-runtimes/releases/download/python%2F3.12.0%2B20231211-040d5a6/python-3.12.0-wasi-sdk-20.0.tar.gz'
SHA='6c1cddbb69ae09e87eee2906bdc70539bff5f2969818a6f8457d4e6a6eb67d4d'
mkdir -p "$DST"
curl -fsSL "$URL" -o "$DST/py.tar.gz"
echo "$SHA  $DST/py.tar.gz" | sha256sum -c -
tar -xzf "$DST/py.tar.gz" -C "$DST"
python3 -m pip install --quiet wasmtime
python3 "$HERE/wasi-python/canaries.py"
