"""Greedy identity: trained MTP head + draft must match no-draft on the same PTQ1_0 target.

  python bench/mtp_identity.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "bin" / "llama-server.exe"
MODEL = Path(os.environ.get(
    "BONSAI_IDENTITY_MODEL",
    str(ROOT / "models" / "Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"),
))
PORT = 8898
PROMPTS = [
    "Write a Python function that merges two sorted lists. Code only.",
    "Explain mmap vs read in one short paragraph.",
]


def kill() -> None:
    subprocess.run(["taskkill", "/F", "/IM", "llama-server.exe"], capture_output=True)
    time.sleep(2)


def wait(proc: subprocess.Popen) -> None:
    t0 = time.time()
    while time.time() - t0 < 240:
        if proc.poll() is not None:
            raise RuntimeError(f"server exited rc={proc.returncode}")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
                if r.status == 200:
                    return
        except Exception:
            pass
        time.sleep(1)
    raise RuntimeError("server not ready")


def start(spec: bool) -> subprocess.Popen:
    cmd = [
        str(BIN), "-m", str(MODEL), "-ngl", "99", "-fa", "on",
        "-c", "8192", "-np", "1", "-ctk", "q8_0", "-ctv", "q8_0",
        "--jinja", "--temp", "0", "--host", "127.0.0.1", "--port", str(PORT),
    ]
    env = dict(os.environ)
    if spec:
        env["GGML_CUDA_BATCH_INVARIANT"] = "1"
        cmd += ["--spec-type", "draft-mtp", "--spec-draft-n-max", "2", "-ctkd", "q8_0", "-ctvd", "q8_0"]
    log = ROOT / "artifacts" / "eval" / ("mtp_id_spec.log" if spec else "mtp_id_plain.log")
    log.parent.mkdir(parents=True, exist_ok=True)
    lf = open(log, "w", encoding="utf-8", errors="replace")
    return subprocess.Popen(cmd, env=env, stdout=lf, stderr=subprocess.STDOUT, cwd=str(BIN.parent))


def chat(prompt: str) -> str:
    body = {
        "model": "b",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 80,
        "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    out = json.loads(urllib.request.urlopen(req, timeout=180).read())
    return ((out.get("choices") or [{}])[0].get("message") or {}).get("content") or ""


def collect(spec: bool) -> list:
    kill()
    proc = start(spec)
    try:
        wait(proc)
        return [chat(p) for p in PROMPTS]
    finally:
        proc.kill()
        proc.wait()


def main() -> int:
    print("== no draft", flush=True)
    plain = collect(False)
    print("== draft n-max 2 + batch-invariant", flush=True)
    spec = collect(True)
    rows = []
    ok = True
    for p, a, b in zip(PROMPTS, plain, spec):
        match = a == b
        ok = ok and match
        rows.append({"prompt": p, "match": match, "plain_n": len(a), "spec_n": len(b)})
        print(("OK" if match else "MISMATCH"), p, f"plain={len(a)} spec={len(b)}", flush=True)
        if not match:
            print("PLAIN:", a[:200], flush=True)
            print("SPEC :", b[:200], flush=True)
    out = ROOT / "artifacts" / "eval" / "mtp_identity.json"
    out.write_text(json.dumps({"ok": ok, "rows": rows, "plain": plain, "spec": spec}, indent=2), encoding="utf-8")
    print("saved", out, "ok=", ok)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
