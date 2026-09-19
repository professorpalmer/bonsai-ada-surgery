from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

src = Path(r"C:\Users\pwall\AppData\Local\Temp\bonsai-ada-build\bin")
dst = Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve\tooling\ada-bin")
for name in (
    "ggml-cuda.dll",
    "llama-bench.exe",
    "llama-server.exe",
    "llama-bench-impl.dll",
    "llama-server-impl.dll",
    "llama.dll",
    "ggml.dll",
):
    s = src / name
    if s.exists():
        shutil.copy2(s, dst / name)
        print("copied", name, s.stat().st_size)
    else:
        print("missing", name)

out = subprocess.check_output(["tasklist"], text=True, errors="replace")
for line in out.splitlines():
    if "llama-server.exe" in line:
        parts = line.split()
        pid = parts[1]
        print("kill", pid)
        subprocess.call(["taskkill", "/PID", pid, "/F"])
