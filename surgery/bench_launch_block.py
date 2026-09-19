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
        pid = line.split()[1]
        subprocess.call(["taskkill", "/PID", pid, "/F"])

bench = Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve\tooling\ada-bin\llama-bench.exe")
model = Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve\models\Ternary-Bonsai-2-27B-PTQ1_0.gguf")
art = Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve\artifacts")
cwd = bench.parent
env = os.environ.copy()
env["PATH"] = str(cwd) + os.pathsep + env.get("PATH", "")
cmd = [str(bench), "-m", str(model), "-ngl", "99", "-fa", "on", "-p", "0", "-n", "128", "-r", "2", "-o", "json"]

env.pop("CUDA_LAUNCH_BLOCKING", None)
p1 = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, errors="replace")
(art / "bench_ptq1_async.json").write_text(p1.stdout, encoding="utf-8")
print("async rc", p1.returncode)
print(p1.stderr[-400:] if p1.stderr else "")

env["CUDA_LAUNCH_BLOCKING"] = "1"
p2 = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, errors="replace")
(art / "bench_ptq1_launchblock.json").write_text(p2.stdout, encoding="utf-8")
print("blocking rc", p2.returncode)
print(p2.stderr[-400:] if p2.stderr else "")
