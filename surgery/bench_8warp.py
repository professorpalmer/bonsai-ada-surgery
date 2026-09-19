from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

src = Path(r"C:\Users\pwall\AppData\Local\Temp\bonsai-ada-build\bin\ggml-cuda.dll")
dst = Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve\tooling\ada-bin\ggml-cuda.dll")
shutil.copy2(src, dst)

out = subprocess.check_output(["tasklist"], text=True, errors="replace")
for line in out.splitlines():
    if "llama-server.exe" in line:
        subprocess.call(["taskkill", "/PID", line.split()[1], "/F"])

bench = Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve\tooling\ada-bin\llama-bench.exe")
model = Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve\models\Ternary-Bonsai-2-27B-PTQ1_0.gguf")
cwd = bench.parent
env = os.environ.copy()
env["PATH"] = str(cwd) + os.pathsep + env.get("PATH", "")
cmd = [str(bench), "-m", str(model), "-ngl", "99", "-fa", "on", "-p", "512", "-n", "128", "-r", "3", "-o", "json"]
p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, errors="replace")
Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve\artifacts\bench_ptq1_mmvq8warp.json").write_text(p.stdout, encoding="utf-8")
print("rc", p.returncode)
print(p.stdout)
