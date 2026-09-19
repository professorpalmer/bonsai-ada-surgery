"""Greedy-generate with llama-server under two env configs and diff the outputs.

usage: python ab_generate.py "ENV=1 ENV2=0" "ENV=0" [n_predict]
Each positional arg is a space-separated env assignment list ("" for baseline).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, "tooling", "ada-bin", "llama-server.exe")
MODEL = os.path.join(ROOT, "models", "Ternary-Bonsai-2-27B-PTQ1_0.gguf")
PORT = 8099

PROMPT = (
    "Write a detailed, step-by-step explanation of how a fast Walsh-Hadamard transform works, "
    "including the butterfly structure, the recursion depth for a vector of length 1024, and why "
    "the normalisation factor is 1/sqrt(n). Then give a short Python implementation."
)


def run(env_spec: str, n_predict: int) -> str:
    env = dict(os.environ)
    for kv in env_spec.split():
        if "=" not in kv:
            continue  # "-" means baseline (PowerShell drops empty args)
        k, v = kv.split("=", 1)
        env[k] = v
    cmd = [BIN, "-m", MODEL, "-ngl", "99", "-fa", "on", "-c", "4096", "--port", str(PORT), "--host", "127.0.0.1",
           "--no-warmup"]
    p = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(600):
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=1) as r:
                    if json.load(r).get("status") == "ok":
                        break
            except Exception:
                pass
            time.sleep(0.25)
        body = json.dumps({"prompt": PROMPT, "n_predict": n_predict, "temperature": 0, "seed": 1,
                           "cache_prompt": False, "ignore_eos": True}).encode()
        req = urllib.request.Request(f"http://127.0.0.1:{PORT}/completion", data=body,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as r:
            res = json.load(r)
        t = res.get("timings", {})
        print(f"[{env_spec or 'baseline'}] tokens={res.get('tokens_predicted')} "
              f"pp={t.get('prompt_per_second', 0):.0f} t/s tg={t.get('predicted_per_second', 0):.2f} t/s")
        return res["content"]
    finally:
        p.kill()
        p.wait()
        time.sleep(1)


def main() -> None:
    a_spec = sys.argv[1] if len(sys.argv) > 1 else ""
    b_spec = sys.argv[2] if len(sys.argv) > 2 else ""
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 160
    a = run(a_spec, n)
    b = run(b_spec, n)
    if a == b:
        print(f"IDENTICAL ({len(a)} chars)")
    else:
        common = 0
        for x, y in zip(a, b):
            if x != y:
                break
            common += 1
        print(f"DIFFER after {common} common chars of {len(a)}/{len(b)}")
        print("--- A ---")
        print(a[:600])
        print("--- B ---")
        print(b[:600])


if __name__ == "__main__":
    main()
