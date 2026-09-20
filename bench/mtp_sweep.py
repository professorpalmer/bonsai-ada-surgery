"""Speculative-decoding (MTP head) sweep on a live llama-server.

Starts llama-server once per arm with identical flags except the --spec-* ones, runs
sudoingX's probe.py (three prompts x three runs, thinking off, 400 tokens) against it,
records the median tok/s per prompt plus the server's draft acceptance lines, and prints
a table. This is the paired protocol from bonsai2-small-gpu/graft/recipe.txt so the
numbers land next to his RTX 3060 receipts.

usage: python bench/mtp_sweep.py --server %TEMP%/combo-build/bin/llama-server.exe \
           --model models/Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf \
           --probe %TEMP%/bonsai2-small-gpu/graft/probe.py --ctx 131072 --out artifacts/mtp_sweep.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ARMS = [
    # name, extra server args, extra env
    ("spec off",            [],                                                   {}),
    ("mtp n-max 1",         ["--spec-type", "draft-mtp", "--spec-draft-n-max", "1"], {}),
    ("mtp n-max 2",         ["--spec-type", "draft-mtp", "--spec-draft-n-max", "2"], {}),
    ("mtp n-max 3",         ["--spec-type", "draft-mtp", "--spec-draft-n-max", "3"], {}),
    ("mtp n-max 1 + batch-invariant", ["--spec-type", "draft-mtp", "--spec-draft-n-max", "1"],
                                      {"GGML_CUDA_BATCH_INVARIANT": "1"}),
    ("mtp n-max 2 + batch-invariant", ["--spec-type", "draft-mtp", "--spec-draft-n-max", "2"],
                                      {"GGML_CUDA_BATCH_INVARIANT": "1"}),
]

PROBE_LINE = re.compile(r"^\s*([\d.]+) tok/s median \| runs: .*? \| (.*)$", re.M)
OVERALL = re.compile(r"OVERALL: mean ([\d.]+) median ([\d.]+)")


def parse_probe(stdout: str) -> dict:
    per = {}
    for m in PROBE_LINE.finditer(stdout):
        prompt = m.group(2)
        label = "bash" if "bash" in prompt else ("code" if prompt.startswith("write") else "prose")
        per[label] = float(m.group(1))
    o = OVERALL.search(stdout)
    if o:
        per["mean"] = float(o.group(1))
    return per


def wait_ready(port: int, proc: subprocess.Popen, timeout: float = 300) -> None:
    t0 = time.time()
    while time.time() - t0 < timeout:
        if proc.poll() is not None:
            raise RuntimeError(f"server exited early rc={proc.returncode}")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as r:
                if r.status == 200:
                    return
        except Exception:  # noqa: BLE001
            pass
        time.sleep(1)
    raise RuntimeError("server did not become ready")


def gpu_mem_mib() -> int:
    try:
        q = subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                           capture_output=True, text=True, timeout=5).stdout.strip()
        return int(float(q.splitlines()[0]))
    except Exception:  # noqa: BLE001
        return -1


def run_arm(name: str, extra: list, env_extra: dict, a: argparse.Namespace) -> dict:
    cmd = [a.server, "-m", a.model, "-ngl", "99", "-fa", "on", "-c", str(a.ctx), "-np", "1",
           "-ctk", "q4_0", "-ctv", "q4_0", "--jinja", "--temp", "1.0", "--top-p", "0.95", "--top-k", "20",
           "--host", "127.0.0.1", "--port", str(a.port)] + extra
    env = dict(os.environ)
    env.update(env_extra)
    log = Path(a.logdir) / (re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_") + ".log")
    with open(log, "w", encoding="utf-8", errors="replace") as lf:
        proc = subprocess.Popen(cmd, env=env, stdout=lf, stderr=subprocess.STDOUT, cwd=str(Path(a.server).parent))
        try:
            wait_ready(a.port, proc)
            time.sleep(2)
            mem = gpu_mem_mib()
            p = subprocess.run([sys.executable, a.probe, f"http://127.0.0.1:{a.port}"],
                               capture_output=True, text=True, errors="replace", timeout=1800)
        finally:
            proc.kill()
            proc.wait()
    per = parse_probe(p.stdout)
    text = log.read_text(encoding="utf-8", errors="replace")
    acc = re.findall(r"draft acceptance rate\s*=\s*([\d.]+)", text)
    acc_alt = re.findall(r"accept(?:ed|ance)[^\n]*?([\d.]+)\s*%", text)
    print(f"[{name}] vram={mem} MiB  " + "  ".join(f"{k}={v:.1f}" for k, v in per.items())
          + (f"  acc={acc[-1]}" if acc else "") + (f"  acc%={acc_alt[-1]}" if acc_alt else ""), flush=True)
    if not per:
        print(p.stdout[-1500:], p.stderr[-1500:], file=sys.stderr)
    return {"name": name, "args": extra, "env": env_extra, "vram_mib": mem, "probe": per,
            "probe_stdout": p.stdout, "acceptance": acc[-1] if acc else None, "log": str(log)}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--probe", required=True)
    ap.add_argument("--ctx", type=int, default=131072)
    ap.add_argument("--port", type=int, default=8899)
    ap.add_argument("--arms", default=None, help="comma-separated arm indices to run (default all)")
    ap.add_argument("--logdir", default=str(Path(os.environ.get("TEMP", ".")) / "mtp_sweep_logs"))
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    for k in ("server", "model", "probe"):
        setattr(a, k, str(Path(os.path.expandvars(getattr(a, k))).resolve()))
    Path(a.logdir).mkdir(parents=True, exist_ok=True)

    arms = ARMS if not a.arms else [ARMS[int(i)] for i in a.arms.split(",")]
    results = [run_arm(n, e, v, a) for n, e, v in arms]

    keys: list = []
    for r in results:
        for k in r["probe"]:
            if k not in keys:
                keys.append(k)
    print("\n| arm | " + " | ".join(keys) + " | VRAM MiB | acceptance |")
    print("|---|" + "---:|" * (len(keys) + 2))
    for r in results:
        print(f"| {r['name']} | " + " | ".join(f"{r['probe'].get(k, float('nan')):.1f}" for k in keys)
              + f" | {r['vram_mib']} | {r['acceptance'] or '-'} |")
    if a.out:
        Path(a.out).write_text(json.dumps({"server": a.server, "model": a.model, "ctx": a.ctx,
                                           "results": results}, indent=2), encoding="utf-8")
        print(f"saved {a.out}")


if __name__ == "__main__":
    main()
