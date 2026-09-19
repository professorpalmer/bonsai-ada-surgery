from __future__ import annotations

"""Run one TG bench while sampling nvidia-smi clocks/power at 100 ms."""

import os
import subprocess
import sys
import time
from pathlib import Path

root = Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve")
dst = root / "tooling" / "ada-bin"
bench = dst / "llama-bench.exe"
model = root / "models" / "Ternary-Bonsai-2-27B-PTQ1_0.gguf"

out = subprocess.check_output(["tasklist"], text=True, errors="replace")
for line in out.splitlines():
    if "llama-server.exe" in line:
        subprocess.call(["taskkill", "/PID", line.split()[1], "/F"])

tag = sys.argv[1] if len(sys.argv) > 1 else "smi"
env = os.environ.copy()
env["PATH"] = str(dst) + os.pathsep + env.get("PATH", "")
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    env[k] = v

smi_log = root / "artifacts" / f"smi_{tag}.csv"
smi = subprocess.Popen(
    ["nvidia-smi", "--query-gpu=timestamp,clocks.sm,clocks.mem,power.draw,temperature.gpu,utilization.gpu,utilization.memory,clocks_event_reasons.active",
     "--format=csv,noheader", "-lms", "100"],
    stdout=open(smi_log, "w", encoding="utf-8"), stderr=subprocess.DEVNULL, text=True)

cmd = [str(bench), "-m", str(model), "-ngl", "99", "-fa", "on", "-p", "0", "-n", "256", "-r", "2", "-o", "json"]
t0 = time.time()
p = subprocess.run(cmd, cwd=dst, env=env, capture_output=True, text=True, errors="replace")
smi.terminate()
import json
try:
    print("tg", json.loads(p.stdout)[-1]["avg_ts"])
except Exception:
    print(p.stderr[-800:])

rows = [l.split(", ") for l in smi_log.read_text(encoding="utf-8").splitlines() if l.strip()]
# keep only rows where gpu util > 50 (bench running)
busy = [r for r in rows if len(r) >= 7 and r[5].split()[0].isdigit() and int(r[5].split()[0]) > 50]
def col(i, conv=float):
    vals = []
    for r in busy:
        try:
            vals.append(conv(r[i].split()[0]))
        except Exception:
            pass
    return vals
sm = col(1); mem = col(2); pw = col(3); tmp = col(4)
if sm:
    print(f"samples={len(busy)} sm_clk min/avg/max={min(sm):.0f}/{sum(sm)/len(sm):.0f}/{max(sm):.0f}  mem_clk={sum(mem)/len(mem):.0f}  power min/avg/max={min(pw):.1f}/{sum(pw)/len(pw):.1f}/{max(pw):.1f}  temp={max(tmp):.0f}")
    reasons = {}
    for r in busy:
        reasons[r[7]] = reasons.get(r[7], 0) + 1
    print("throttle reasons:", reasons)
