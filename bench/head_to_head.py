"""Paired llama-bench comparison of several builds on one card.

Runs the arms in alternating order (a, b, c, a, b, c, ...) so clock and thermal drift
hits every arm equally, records SM/memory clock while running, and prints a table.
Used for the PrismML-Eng/llama.cpp #215 vs #218 comparison on the RTX 4070.

usage: python bench/head_to_head.py --model models/Ternary-Bonsai-2-27B-PTQ1_0.gguf \
           --arm stock=tooling/stock-bin --arm ours=%TEMP%/bonsai-ada-build/bin \
           --arm pr218=%TEMP%/pr218-build/bin --rounds 2 --out artifacts/h2h.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
import threading
import time
from pathlib import Path

# "| pp512 | 1307.87 ± 21.18 |"; the separator is matched loosely because the binary prints UTF-8 and
# the console code page may mangle the plus-minus sign
ROW = re.compile(r"\|\s*(pp\d+|tg\d+)\s*\|\s*([\d.]+)\s*[^\d|]+?\s*([\d.]+)\s*\|")


def sample_clocks(stop: threading.Event, out: list) -> None:
    while not stop.is_set():
        try:
            q = subprocess.run(
                ["nvidia-smi", "--query-gpu=clocks.sm,clocks.mem,power.draw,utilization.gpu",
                 "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=5,
            ).stdout.strip()
            sm, mem, pw, util = [float(x) for x in q.split(",")]
            if util > 50:
                out.append((sm, mem, pw))
        except Exception:
            pass
        stop.wait(0.25)


def run_arm(name: str, bindir: Path, model: Path, tests_p: str, n: int, reps: int, env_extra: dict) -> dict:
    exe = bindir / "llama-bench.exe"
    cmd = [str(exe), "-m", str(model), "-ngl", "99", "-fa", "1", "-ctk", "q4_0", "-ctv", "q4_0",
           "-p", tests_p, "-n", str(n), "-r", str(reps), "-o", "md"]
    env = dict(os.environ)
    env.update(env_extra)
    samples: list = []
    stop = threading.Event()
    t = threading.Thread(target=sample_clocks, args=(stop, samples), daemon=True)
    t.start()
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, cwd=str(bindir))
    stop.set()
    t.join()
    res = {}
    for m in ROW.finditer(p.stdout):
        res[m.group(1)] = (float(m.group(2)), float(m.group(3)))
    if not res:
        print(f"[{name}] no rows parsed; rc={p.returncode}\n{p.stdout[-2000:]}\n{p.stderr[-2000:]}", file=sys.stderr)
    clk = {}
    if samples:
        clk = {
            "sm_mhz": round(statistics.median(s[0] for s in samples)),
            "mem_mhz": round(statistics.median(s[1] for s in samples)),
            "power_w": round(statistics.median(s[2] for s in samples), 1),
        }
    print(f"[{name}] {time.time() - t0:5.1f}s  " + "  ".join(f"{k}={v[0]:.2f}" for k, v in res.items()) + f"  {clk}",
          flush=True)
    return {"results": res, "clocks": clk}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--arm", action="append", required=True, help="name=bindir[;ENV=VAL;ENV2=VAL]")
    ap.add_argument("--rounds", type=int, default=2)
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--p", default="512,1,2,4,8", help="prompt batch sizes for llama-bench -p")
    ap.add_argument("--n", type=int, default=128)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    arms = []
    for spec in a.arm:
        name, rest = spec.split("=", 1)
        parts = rest.split(";")
        bindir = Path(os.path.expandvars(parts[0])).resolve()
        env = dict(kv.split("=", 1) for kv in parts[1:] if "=" in kv)
        arms.append((name, bindir, env))

    model = Path(a.model).resolve()
    runs: dict = {name: [] for name, _, _ in arms}
    for r in range(a.rounds):
        for name, bindir, env in arms:
            runs[name].append(run_arm(name, bindir, model, a.p, a.n, a.reps, env))

    tests = []
    for name in runs:
        for run in runs[name]:
            for k in run["results"]:
                if k not in tests:
                    tests.append(k)

    summary = {}
    print("\n| test | " + " | ".join(n for n, _, _ in arms) + " |")
    print("|---|" + "---:|" * len(arms))
    for tname in tests:
        row = []
        for name, _, _ in arms:
            vals = [run["results"][tname][0] for run in runs[name] if tname in run["results"]]
            v = statistics.mean(vals) if vals else float("nan")
            summary.setdefault(name, {})[tname] = v
            row.append(f"{v:.2f}")
        print(f"| {tname} | " + " | ".join(row) + " |")
    clk_row = []
    for name, _, _ in arms:
        cl = [run["clocks"] for run in runs[name] if run["clocks"]]
        clk_row.append(f"{cl[-1]['sm_mhz']}/{cl[-1]['mem_mhz']} MHz {cl[-1]['power_w']} W" if cl else "-")
    print("| clocks (sm/mem), power | " + " | ".join(clk_row) + " |")

    if a.out:
        Path(a.out).write_text(json.dumps({"model": str(model), "arms": [
            {"name": n, "bindir": str(b), "env": e} for n, b, e in arms], "runs": runs, "summary": summary},
            indent=2), encoding="utf-8")
        print(f"saved {a.out}")


if __name__ == "__main__":
    main()
