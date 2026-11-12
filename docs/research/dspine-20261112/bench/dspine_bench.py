"""DSpine vs MTP vs no draft on Bonsai 2 27B (RTX 4070 12 GB).

One cell = one fresh llama-server (one arm, one depth). The runner starts the server hidden with
PowerShell Start-Process -PassThru (log file), waits for /health, runs a warm-up, then a code prompt and a prose
prompt (each with its own filler, so each first request measures prefill), REPEATS requests per prompt (greedy,
thinking off), samples nvidia-smi during the requests, stops the server by PID and checks that no llama-server is
left and VRAM is back to the baseline. One JSON line per cell goes to --out; the full texts go to --texts.

python dspine_bench.py --plan DS1-plan.json --cells a:1500,b:1500 --out runs-raw.jsonl --texts texts.jsonl
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import threading
import time
import urllib.request

PORT = 8897
BASE = f"http://127.0.0.1:{PORT}"

PROMPTS = {
    "code": "Write a Python module that implements an LRU cache class with get, put, delete and resize methods, "
            "type hints and docstrings, followed by unittest tests for each method. Output only the code.",
    "prose": "Write a detailed essay of about 600 words on the history of the transistor, from the point-contact "
             "device to modern integrated circuits. Use plain paragraphs, no headings.",
}


def http(path, body=None, timeout=1800):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read())


def smi(query):
    out = subprocess.run(["nvidia-smi", f"--query-gpu={query}", "--format=csv,noheader,nounits"],
                         capture_output=True, text=True).stdout.strip().splitlines()[0]
    return [x.strip() for x in out.split(",")]


def ps(cmd):
    return subprocess.run(["powershell", "-NoProfile", "-Command", cmd], capture_output=True, text=True)


def server_pids():
    r = ps("Get-Process llama-server -ErrorAction SilentlyContinue | ForEach-Object { $_.Id }")
    return [int(x) for x in r.stdout.split()]


def filler(src_text, target_tokens):
    """A slice of src_text of about target_tokens tokens (server tokenizer), cut at a line end."""
    n_chars = target_tokens * 4
    for _ in range(4):
        txt = src_text[:n_chars]
        txt = txt[: txt.rfind("\n") + 1] or txt
        got = len(http("/tokenize", {"content": txt})["tokens"])
        if abs(got - target_tokens) < 0.03 * target_tokens:
            break
        n_chars = int(n_chars * target_tokens / max(1, got))
    return txt


def request(prompt, max_tokens):
    body = {
        "model": "b",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0,
        "top_k": 1,
        "seed": 1,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    t0 = time.time()
    r = http("/v1/chat/completions", body)
    r["_wall"] = time.time() - t0
    return r


class Sampler(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.stop_ev = threading.Event()
        self.mem_used, self.clk = [], []

    def run(self):
        while not self.stop_ev.is_set():
            try:
                used, clk, util = smi("memory.used,clocks.mem,utilization.gpu")
                self.mem_used.append(int(used))
                if int(util) > 50:
                    self.clk.append(int(clk))
            except Exception:
                pass
            self.stop_ev.wait(2.0)


def start_server(exe_dir, args, env, log):
    env_ps = "; ".join(f"$env:{k}='{v}'" for k, v in env.items())
    arglist = ",".join("'" + a.replace("'", "''") + "'" for a in args)
    cmd = (f"{env_ps}; $p = Start-Process -FilePath '{exe_dir}\\llama-server.exe' -ArgumentList {arglist} "
           f"-WorkingDirectory '{exe_dir}' -WindowStyle Hidden -RedirectStandardOutput '{log}.out' "
           f"-RedirectStandardError '{log}' -PassThru; $p.Id")
    # no pipes here: the server inherits the PowerShell handles, and a pipe would stay open until the server exits
    pid_file = log + ".pid"
    with open(pid_file, "w") as f:
        subprocess.run(["powershell", "-NoProfile", "-Command", cmd], stdin=subprocess.DEVNULL, stdout=f, stderr=f)
    return int(open(pid_file).read().strip().splitlines()[-1])


def stop_server(pid, baseline_mib):
    ps(f"Stop-Process -Id {pid} -Force -ErrorAction SilentlyContinue")
    for _ in range(60):
        time.sleep(1)
        if not server_pids():
            break
    left = server_pids()
    used = int(smi("memory.used")[0])
    return {"left_pids": left, "mem_after_stop_mib": used, "baseline_mib": baseline_mib}


def run_cell(plan, arm_id, depth, a):
    arm = plan["arms"][arm_id]
    common = plan["server"]
    ctx = str(arm.get("ctx", common["ctx"]))
    args = [*common["args"], "-c", ctx, "-m", arm["model"], *arm.get("args", []), "--port", str(PORT)]
    env = {**common.get("env", {}), **arm.get("env", {})}
    tag = f"{arm_id}_d{depth}"
    log = os.path.join(a.logdir, f"{tag}.err.log")
    baseline = int(smi("memory.used")[0])
    t_start = time.time()
    pid = start_server(plan["exe_dir"], args, env, log)
    cell = {"cell": tag, "arm": arm_id, "depth": depth, "args": args, "env": env, "baseline_mib": baseline,
            "start": time.strftime("%Y-%m-%dT%H:%M:%S")}
    ok = False
    for _ in range(600):
        time.sleep(1)
        try:
            if http("/health", timeout=5).get("status") == "ok":
                ok = True
                break
        except Exception:
            pass
        if pid not in server_pids():
            break
    if not ok:
        cell["error"] = "server did not start"
        cell["log_tail"] = open(log, encoding="utf-8", errors="replace").read()[-3000:]
        cell["stop"] = stop_server(pid, baseline)
        return cell
    cell["load_s"] = round(time.time() - t_start, 1)
    cell["mem_loaded_mib"] = int(smi("memory.used")[0])
    request("Say hi.", 8)
    srcs = {"code": open(plan["filler"]["code"], encoding="utf-8", errors="replace").read(),
            "prose": open(plan["filler"]["prose"], encoding="utf-8", errors="replace").read()}
    samp = Sampler()
    samp.start()
    results = {}
    for name, prompt in PROMPTS.items():
        fill = filler(srcs[name], depth) if depth > 0 else ""
        full = (("Reference material (do not summarize it; answer the request after it):\n\n" + fill + "\n\n")
                if fill else "") + prompt
        reps = []
        for rep in range(a.repeats):
            try:
                r = request(full, plan["max_tokens"])
            except Exception as e:  # a crash mid-cell is a result, keep it
                reps.append({"error": repr(e)})
                break
            t = r.get("timings", {})
            text = r["choices"][0]["message"].get("content") or ""
            reps.append({
                "prompt_n": t.get("prompt_n"), "prefill_tps": t.get("prompt_per_second"),
                "predicted_n": t.get("predicted_n"), "decode_tps": t.get("predicted_per_second"),
                "draft_n": t.get("draft_n"), "draft_accepted": t.get("draft_n_accepted"),
                "wall_s": round(r["_wall"], 2), "text200": text[:200],
            })
            with open(a.texts, "a", encoding="utf-8") as f:
                f.write(json.dumps({"cell": tag, "prompt": name, "rep": rep, "text": text}) + "\n")
        results[name] = reps
    samp.stop_ev.set()
    samp.join()
    cell["results"] = results
    cell["mem_peak_mib"] = max(samp.mem_used) if samp.mem_used else None
    cell["mem_clock_busy"] = sorted(set(samp.clk))
    try:
        cell["log_spec"] = [l.strip() for l in open(log, encoding="utf-8", errors="replace")
                            if any(k in l for k in ("draft acceptance", "DSpine", "CUDA0 model buffer", "CUDA0 KV buffer",
                                                    "CUDA0 compute buffer", "rollback", "RS buffer", "causal_attn"))][:40]
    except Exception:
        pass
    cell["stop"] = stop_server(pid, baseline)
    cell["end"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    return cell


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cells", required=True, help="arm:depth,arm:depth,...")
    ap.add_argument("--out", required=True)
    ap.add_argument("--texts", required=True)
    ap.add_argument("--logdir", required=True)
    ap.add_argument("--repeats", type=int, default=2)
    a = ap.parse_args()
    plan = json.load(open(a.plan, encoding="utf-8"))
    os.makedirs(a.logdir, exist_ok=True)
    for spec in a.cells.split(","):
        arm_id, depth = spec.split(":")
        if server_pids():
            print("a llama-server is running: stop", flush=True)
            break
        cell = run_cell(plan, arm_id, int(depth), a)
        with open(a.out, "a", encoding="utf-8") as f:
            f.write(json.dumps(cell) + "\n")
        brief = {k: [(x.get("decode_tps"), x.get("draft_n"), x.get("draft_accepted")) for x in v]
                 for k, v in cell.get("results", {}).items()}
        print(cell["cell"], cell.get("error", ""), brief, cell.get("mem_loaded_mib"), cell.get("mem_clock_busy"), flush=True)
        if cell.get("stop", {}).get("left_pids"):
            print("server left after stop: abort", flush=True)
            break


if __name__ == "__main__":
    main()
