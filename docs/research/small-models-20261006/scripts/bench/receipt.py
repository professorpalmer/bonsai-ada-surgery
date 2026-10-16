"""Bonsai 2 27B "receipt sheet" for one GPU, in the same shape as the community 12 GB sheet:
decode speed by context depth, prefill at 2k and 35k, resident VRAM per context window,
live-server TTFT + fresh decode, and power / tok/s-per-watt. Same serve flags as the sheet:
PTQ1_0, -fa on, q4_0 KV, one slot, --jinja.

usage: python bench/receipt.py [tag] [--bin DIR] [--model FILE] [--skip-footprint] [--quick]
Writes artifacts/receipt_<tag>.json and prints a markdown table.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEPTHS = [7168, 12288, 35840, 77824]
WINDOWS = [65536, 131072, 196608, 262144]
PORT = 8898


class SmiSampler:
    """Sample power/clocks/temp at 100 ms; report averages over busy (util > 50) samples."""

    def __init__(self) -> None:
        self.rows: list[list[str]] = []
        self.proc = None
        self.thread = None

    def start(self) -> None:
        self.proc = subprocess.Popen(
            ["nvidia-smi", "--query-gpu=power.draw,clocks.sm,clocks.mem,temperature.gpu,utilization.gpu,fan.speed",
             "--format=csv,noheader,nounits", "-lms", "100"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.thread = threading.Thread(target=self._pump, daemon=True)
        self.thread.start()

    def _pump(self) -> None:
        for line in self.proc.stdout:
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 5:
                self.rows.append(parts)

    def stop(self) -> None:
        self.proc.terminate()
        self.thread.join(timeout=2)

    def summary(self, since: int) -> dict:
        busy = []
        for r in self.rows[since:]:
            try:
                if float(r[4]) > 50:
                    busy.append([float(x) if x not in ("[N/A]", "N/A") else 0.0 for x in r[:6]])
            except ValueError:
                pass
        if not busy:
            return {}
        n = len(busy)
        return {
            "power_w": round(sum(b[0] for b in busy) / n, 1),
            "power_max_w": round(max(b[0] for b in busy), 1),
            "sm_mhz": round(sum(b[1] for b in busy) / n),
            "mem_mhz": round(sum(b[2] for b in busy) / n),
            "temp_c": round(max(b[3] for b in busy)),
            "fan_pct": round(max(b[5] for b in busy)),
            "samples": n,
        }


def kill_servers() -> None:
    subprocess.call(["taskkill", "/IM", "llama-server.exe", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)


def llama_bench(bench: Path, model: Path, args: list[str]) -> list[dict]:
    cmd = [str(bench), "-m", str(model), "-ngl", "99", "-fa", "on", "-ctk", "q4_0", "-ctv", "q4_0", "-o", "json"] + args
    p = subprocess.run(cmd, cwd=bench.parent, capture_output=True, text=True, errors="replace")
    if p.returncode != 0:
        print(p.stderr[-1500:], file=sys.stderr)
        raise SystemExit(f"llama-bench failed: {' '.join(args)}")
    return json.loads(p.stdout)


def gpu_name() -> str:
    return subprocess.check_output(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"], text=True).strip()


def gpu_used_mib() -> tuple[int, int]:
    total = subprocess.check_output(["nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,noheader,nounits"],
                                    text=True).strip().split(",")
    return int(total[0]), int(total[1])


def server_footprint(server: Path, model: Path, ctx: int, live: bool) -> dict:
    kill_servers()
    time.sleep(2)
    before, _ = gpu_used_mib()
    cmd = [str(server), "-m", str(model), "-ngl", "99", "-fa", "on", "-c", str(ctx), "-np", "1", "-ctk", "q4_0",
           "-ctv", "q4_0", "--jinja", "--temp", "1.0", "--top-p", "0.95", "--top-k", "20", "--host", "127.0.0.1",
           "--port", str(PORT)]
    p = subprocess.Popen(cmd, cwd=server.parent, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    res: dict = {"ctx": ctx}
    try:
        ok = False
        for _ in range(1200):
            if p.poll() is not None:
                break
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=1) as r:
                    if json.load(r).get("status") == "ok":
                        ok = True
                        break
            except Exception:
                pass
            time.sleep(0.25)
        if not ok:
            res["error"] = "server did not come up (OOM?)"
            return res
        time.sleep(1.5)
        # Per-process usage is [N/A] under WDDM; use the whole-GPU delta around server start.
        used, total = gpu_used_mib()
        res["resident_mib"] = used - before
        res["gpu_used_mib"] = used
        res["gpu_total_mib"] = total
        if live:
            prompt = ("You are auditing a CUDA kernel. " * 230)  # ~2k tokens
            body = json.dumps({"prompt": prompt, "n_predict": 256, "temperature": 0, "ignore_eos": True,
                               "cache_prompt": False}).encode()
            req = urllib.request.Request(f"http://127.0.0.1:{PORT}/completion", data=body,
                                         headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=600) as r:
                t = json.load(r)["timings"]
            res["live"] = {
                "prompt_tokens": t["prompt_n"],
                "prefill_tps": round(t["prompt_per_second"], 1),
                "ttft_s": round(t["prompt_ms"] / 1000, 2),
                "decode_tps": round(t["predicted_per_second"], 2),
            }
    finally:
        p.kill()
        p.wait()
    return res


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("tag", nargs="?", default="receipt")
    ap.add_argument("--bin", default=str(ROOT / "bin"))
    ap.add_argument("--model", default=str(ROOT / "models" / "Ternary-Bonsai-2-27B-PTQ1_0.gguf"))
    ap.add_argument("--skip-footprint", action="store_true")
    ap.add_argument("--quick", action="store_true", help="depths up to 12k only")
    ap.add_argument("--footprint-only", action="store_true", help="reuse artifacts/receipt_<tag>.json, redo footprint")
    a = ap.parse_args()
    bench = Path(a.bin) / "llama-bench.exe"
    server = Path(a.bin) / "llama-server.exe"
    model = Path(a.model)
    dst = ROOT / "artifacts" / f"receipt_{a.tag}.json"
    dst.parent.mkdir(exist_ok=True)

    kill_servers()
    smi = SmiSampler()
    smi.start()
    out: dict = {"gpu": gpu_name(), "model": model.name, "kv": "q4_0", "tag": a.tag,
                 "date": time.strftime("%Y-%m-%d %H:%M"), "depth": [], "prefill": [], "footprint": []}
    if a.footprint_only and dst.exists():
        out = json.loads(dst.read_text(encoding="utf-8"))
        out["footprint"] = []

    def save() -> None:
        dst.write_text(json.dumps(out, indent=2), encoding="utf-8")

    depths = [] if a.footprint_only else (DEPTHS[:2] if a.quick else DEPTHS)
    for d in depths:
        since = len(smi.rows)
        reps = "2" if d <= 12288 else "1"
        r = llama_bench(bench, model, ["-p", "0", "-n", "128", "-d", str(d), "-r", reps])[-1]
        s = smi.summary(since)
        out["depth"].append({"depth": d, "tg_tps": round(r["avg_ts"], 2), "stddev": round(r.get("stddev_ts", 0), 2), **s})
        print(f"depth {d:>6}: {r['avg_ts']:.2f} tok/s  {s}", flush=True)
        save()

    if not a.footprint_only:
        since = len(smi.rows)
        r = llama_bench(bench, model, ["-p", "2048", "-n", "0", "-d", "0", "-r", "2"])[-1]
        out["prefill"].append({"prompt": 2048, "depth": 0, "pp_tps": round(r["avg_ts"], 1), **smi.summary(since)})
        print(f"prefill 2048 @0: {r['avg_ts']:.1f} tok/s", flush=True)
        if not a.quick:
            since = len(smi.rows)
            r = llama_bench(bench, model, ["-p", "2048", "-n", "0", "-d", "35840", "-r", "1"])[-1]
            out["prefill"].append({"prompt": 2048, "depth": 35840, "pp_tps": round(r["avg_ts"], 1), **smi.summary(since)})
            print(f"prefill 2048 @35840: {r['avg_ts']:.1f} tok/s", flush=True)
        since = len(smi.rows)
        r = llama_bench(bench, model, ["-p", "0", "-n", "256", "-d", "0", "-r", "3"])[-1]
        s = smi.summary(since)
        out["fresh_decode"] = {"tg_tps": round(r["avg_ts"], 2), **s}
        if s.get("power_w"):
            out["fresh_decode"]["tps_per_watt"] = round(r["avg_ts"] / s["power_w"], 3)
        print(f"fresh decode: {r['avg_ts']:.2f} tok/s  {s}", flush=True)
        save()

    if not a.skip_footprint:
        for w in WINDOWS:
            fp = server_footprint(server, model, w, live=(w in (65536, 262144)))
            out["footprint"].append(fp)
            print(f"window {w:>7}: {fp}", flush=True)
            save()
    smi.stop()
    save()

    def klabel(n: int) -> str:  # match the community sheet: 7k/12k/35k/77k, 64k/128k/192k/262k
        return "262k" if n == 262144 else f"{n // 1024}k" if n % 1024 == 0 else f"{n // 1000}k"

    print(f"\n### {out['gpu']} - {model.name} - KV q4_0 - {out['date']}\n")
    print("| depth | decode tok/s | power W | SM MHz | mem MHz |")
    print("| ---: | ---: | ---: | ---: | ---: |")
    for d in out["depth"]:
        print(f"| {klabel(d['depth'])} | {d['tg_tps']} | {d.get('power_w','')} | {d.get('sm_mhz','')} | {d.get('mem_mhz','')} |")
    print()
    for p in out["prefill"]:
        print(f"- prefill {p['prompt']} tokens at depth {klabel(p['depth'])}: {p['pp_tps']} tok/s")
    fd = out["fresh_decode"]
    print(f"- fresh decode (depth 0): {fd['tg_tps']} tok/s at {fd.get('power_w','?')} W = {fd.get('tps_per_watt','?')} tok/s/W, "
          f"{fd.get('temp_c','?')} C, fan {fd.get('fan_pct','?')}%")
    if out["footprint"]:
        print("\n| window | resident (server process) | GPU total used |")
        print("| ---: | ---: | ---: |")
        for f in out["footprint"]:
            if "error" in f:
                print(f"| {klabel(f['ctx'])} | {f['error']} | |")
            else:
                print(f"| {klabel(f['ctx'])} | {f.get('resident_mib',0)/1024:.1f} GB | {f['gpu_used_mib']/1024:.1f} / {f['gpu_total_mib']/1024:.1f} GB |")
        for f in out["footprint"]:
            if "live" in f:
                l = f["live"]
                print(f"- live server, {klabel(f['ctx'])} window: {l['prompt_tokens']}-token prompt prefill {l['prefill_tps']} tok/s, "
                      f"TTFT {l['ttft_s']} s, decode {l['decode_tps']} tok/s")


if __name__ == "__main__":
    main()
