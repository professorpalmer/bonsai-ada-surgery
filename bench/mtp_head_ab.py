"""A/B teacher MTP graft vs ProCreations on-policy head, both on official PTQ1_0.

Same shipped flags: 96k / q8_0 / draft-mtp n-max 2 / batch-invariant / think off.
Uses sudoingX probe.py (3 prompts x 3 runs x 400 tokens) plus server acceptance lines.

  python bench/mtp_head_ab.py
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin" / "llama-server.exe"
PROBE = ROOT / "models" / "donor" / "bonsai2-small-gpu" / "graft" / "probe.py"
PORT = 8899
CTX = 98304
CTK = "q8_0"

ARMS = [
    ("teacher Q4_K graft", ROOT / "models" / "Ternary-Bonsai-2-27B-PTQ1_0-mtp-lean.gguf"),
    ("procreations Q8 trained", ROOT / "models" / "Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"),
]


def kill_servers() -> None:
    subprocess.run(["taskkill", "/F", "/IM", "llama-server.exe"], capture_output=True)
    time.sleep(2)


def wait_ready(proc: subprocess.Popen, timeout: float = 240) -> None:
    t0 = time.time()
    while time.time() - t0 < timeout:
        if proc.poll() is not None:
            raise RuntimeError(f"server exited early rc={proc.returncode}")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
                if r.status == 200:
                    return
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError("server did not become ready")


def gpu_mem() -> int:
    q = subprocess.run(
        ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
        capture_output=True, text=True, timeout=5,
    ).stdout.strip()
    return int(float(q.splitlines()[0]))


def parse_probe(stdout: str) -> dict:
    per = {}
    for m in re.finditer(r"^\s*([\d.]+) tok/s median \| runs: .*? \| (.*)$", stdout, re.M):
        prompt = m.group(2)
        label = "bash" if "bash" in prompt else ("code" if prompt.startswith("write") else "prose")
        per[label] = float(m.group(1))
    o = re.search(r"OVERALL: mean ([\d.]+) median ([\d.]+)", stdout)
    if o:
        per["mean"] = float(o.group(1))
        per["median"] = float(o.group(2))
    return per


def run_arm(name: str, model: Path, logdir: Path) -> dict:
    if not model.is_file():
        raise FileNotFoundError(model)
    log = logdir / (re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_") + ".log")
    cmd = [
        str(BIN), "-m", str(model), "-ngl", "99", "-fa", "on",
        "-c", str(CTX), "-np", "1", "-b", "2048", "-ub", "512",
        "-ctk", CTK, "-ctv", CTK, "--jinja",
        "--temp", "1.0", "--top-p", "0.95", "--top-k", "20",
        "--spec-type", "draft-mtp", "--spec-draft-n-max", "2",
        "-ctkd", CTK, "-ctvd", CTK,
        "--host", "127.0.0.1", "--port", str(PORT),
        "--prio", "2", "--poll", "100",
    ]
    env = dict(os.environ)
    env["GGML_CUDA_BATCH_INVARIANT"] = "1"
    print(f"== {name}  {model.name}", flush=True)
    kill_servers()
    with open(log, "w", encoding="utf-8", errors="replace") as lf:
        proc = subprocess.Popen(
            cmd, env=env, stdout=lf, stderr=subprocess.STDOUT,
            cwd=str(BIN.parent),
        )
        try:
            wait_ready(proc)
            time.sleep(2)
            mem = gpu_mem()
            p = subprocess.run(
                [sys.executable, str(PROBE), f"http://127.0.0.1:{PORT}"],
                capture_output=True, text=True, errors="replace", timeout=1800,
            )
        finally:
            proc.kill()
            proc.wait()
    text = log.read_text(encoding="utf-8", errors="replace")
    acc = re.findall(r"draft acceptance\s*=\s*([\d.]+)", text)
    acc_pct = re.findall(r"(\d+)\s+accepted\s*/\s*(\d+)\s+generated", text)
    per = parse_probe(p.stdout)
    print(p.stdout, flush=True)
    if not per:
        print(p.stderr[-2000:], file=sys.stderr)
    last_acc = float(acc[-1]) if acc else None
    accepted = proposed = None
    if acc_pct:
        accepted = sum(int(a) for a, _ in acc_pct)
        proposed = sum(int(b) for _, b in acc_pct)
    print(
        f"[{name}] vram={mem} MiB  mean={per.get('mean')}  "
        f"acc_last={last_acc}  accepted/proposed={accepted}/{proposed}",
        flush=True,
    )
    return {
        "name": name,
        "model": model.name,
        "vram_mib": mem,
        "probe": per,
        "probe_stdout": p.stdout,
        "acceptance_last": last_acc,
        "accepted": accepted,
        "proposed": proposed,
        "acceptance_lines": acc[-8:],
        "log": str(log),
    }


def main() -> int:
    logdir = ROOT / "artifacts" / "eval" / "mtp_head_ab"
    logdir.mkdir(parents=True, exist_ok=True)
    results = [run_arm(n, m, logdir) for n, m in ARMS]
    out = ROOT / "artifacts" / "eval" / "mtp_head_ab.json"
    out.write_text(json.dumps({"ctx": CTX, "kv": CTK, "spec_n_max": 2, "results": results}, indent=2), encoding="utf-8")
    print("\n| head | code | prose | bash | mean | VRAM | acceptance |")
    print("|---|---:|---:|---:|---:|---:|---:|")
    for r in results:
        p = r["probe"]
        acc = r["acceptance_last"]
        acc_s = f"{acc:.3f}" if isinstance(acc, float) else "-"
        if r["accepted"] and r["proposed"]:
            acc_s += f" ({r['accepted']}/{r['proposed']})"
        print(
            f"| {r['name']} | {p.get('code', float('nan')):.1f} | {p.get('prose', float('nan')):.1f} | "
            f"{p.get('bash', float('nan')):.1f} | {p.get('mean', float('nan')):.1f} | {r['vram_mib']} | {acc_s} |"
        )
    print(f"saved {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
