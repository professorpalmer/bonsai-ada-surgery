from __future__ import annotations

"""Env-knob sweep for TG on the Ada build. Kills the live server first.

usage: python bench_sweep.py <tag> [KEY=VAL ...]
Each KEY=VAL group separated by '--' is one config. Example:
  python bench_sweep.py knobs -- base -- GGML_CUDA_DISABLE_GRAPHS=1 -- GGML_CUDA_DISABLE_FUSION=1
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(r"C:\Users\pwall\Projects\bonsai-2-27b-serve")
dst = root / "tooling" / "ada-bin"
bench = dst / "llama-bench.exe"
model = root / "models" / "Ternary-Bonsai-2-27B-PTQ1_0.gguf"

import shutil
import time

out = subprocess.check_output(["tasklist"], text=True, errors="replace")
for line in out.splitlines():
    if "llama-server.exe" in line:
        subprocess.call(["taskkill", "/PID", line.split()[1], "/F"])
        time.sleep(1.0)

build_bin = Path(r"C:\Users\pwall\AppData\Local\Temp\bonsai-ada-build\bin")
for name in ("ggml-cuda.dll", "ggml-base.dll", "ggml.dll", "llama.dll", "llama-bench.exe", "llama-bench-impl.dll", "llama-server.exe"):
    s = build_bin / name
    if s.exists() and (not (dst / name).exists() or s.stat().st_mtime > (dst / name).stat().st_mtime):
        try:
            shutil.copy2(s, dst / name)
            print("copied", name, flush=True)
        except PermissionError as e:
            print("copy failed", name, e, flush=True)

tag = sys.argv[1]
groups: list[list[str]] = [[]]
for a in sys.argv[2:]:
    if a == "--":
        groups.append([])
    else:
        groups[-1].append(a)
groups = [g for g in groups if g]

results = []
for g in groups:
    env = os.environ.copy()
    env["PATH"] = str(dst) + os.pathsep + env.get("PATH", "")
    label = []
    extra = []
    for kv in g:
        if kv.startswith("-"):
            extra.extend(kv.split("=", 1))
            label.append(kv)
        elif "=" in kv:
            k, v = kv.split("=", 1)
            env[k] = v
            label.append(kv)
        else:
            label.append(kv)
    label = " ".join(label) or "base"
    base_args = ["-p", "0", "-n", "128", "-r", "3"]
    if any(a in ("-n", "-r", "-p") for a in extra):
        base_args = [a for a in base_args if a not in ("-n", "-r", "-p")]
        base_args = []
    cmd = [str(bench), "-m", str(model), "-ngl", "99", "-fa", "on"] + base_args + ["-o", "json", "-v"] + extra
    p = subprocess.run(cmd, cwd=dst, env=env, capture_output=True, text=True, errors="replace")
    ts = None
    try:
        arr = json.loads(p.stdout)
        ts = arr[-1]["avg_ts"]
    except Exception:
        pass
    nodes = re.findall(r"graph nodes\s*=\s*([^\n]+)", p.stderr)
    splits = re.findall(r"graph splits\s*=\s*([^\n]+)", p.stderr)
    stats = [l for l in p.stderr.splitlines() if "[graph-stats]" in l]
    detail = [l for l in p.stderr.splitlines() if "[op-detail]" in l]
    timing = [l for l in p.stderr.splitlines() if "[op-timing]" in l]
    for l in detail:
        print("   ", l.split("[op-detail]", 1)[1].rstrip(), flush=True)
    if timing:
        # keep only the last report block
        starts = [k for k, l in enumerate(timing) if "per-graph avg" in l]
        timing = timing[starts[-1]:] if starts else timing
        stats += timing
    print(f"[{label}] tg128={ts} nodes={nodes[:1]} splits={splits[:1]} rc={p.returncode}", flush=True)
    for l in stats:
        tag_ = "[graph-stats]" if "[graph-stats]" in l else "[op-timing]"
        print("   ", l.split(tag_, 1)[1].rstrip(), flush=True)
    if ts is None:
        print(p.stderr[-1500:])
    results.append({"label": label, "tg128": ts, "nodes": nodes[:1], "splits": splits[:1], "stderr_tail": p.stderr[-3000:]})

(root / "artifacts" / f"sweep_{tag}.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
