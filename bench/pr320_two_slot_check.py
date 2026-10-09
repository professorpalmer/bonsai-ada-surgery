"""PrismML #320 serving check: --spec-draft-window with two slots. Slot 1 answers a short prompt (B1); slot 0 then
runs alone deep past the window (A); slot 1 then continues its own conversation (B2), so its draft rows must still
be there. Compared with a one-slot run of B1 and B2 only: B2 greedy text and draft acceptance should match. The
script starts and stops its own llama-server on port 8899 (it kills only that process).
    python bench/pr320_two_slot_check.py --bin <dir with llama-server.exe> --model <MTP gguf> --out receipts/pr320_two_slot.log
"""
import argparse, hashlib, json, os, subprocess, sys, time, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--bin", required=True)
ap.add_argument("--model", required=True)
ap.add_argument("--window", type=int, default=1024)
ap.add_argument("--deep", type=int, default=8000, help="approximate prompt tokens of the deep request A")
ap.add_argument("--out", default="receipts/pr320_two_slot.log")
a = ap.parse_args()
PORT = 8899
log = open(a.out, "a", encoding="utf-8")


def say(s):
    line = time.strftime("%H:%M ") + s
    print(line, flush=True)
    log.write(line + "\n"); log.flush()


def start(n_slots):
    args = [os.path.join(a.bin, "llama-server.exe"), "-m", a.model, "-ngl", "99", "-fa", "on", "-ctk", "q8_0", "-ctv", "q8_0",
            "-np", str(n_slots), "-c", str(16384 * n_slots), "--port", str(PORT), "--host", "127.0.0.1",
            "--spec-type", "draft-mtp", "--spec-draft-n-max", "2", "--spec-draft-window", str(a.window), "--jinja"]
    errf = open(os.path.join("logs", f"pr320_np{n_slots}.server.log"), "w")
    env = dict(os.environ, PATH=a.bin + os.pathsep + os.environ.get("PATH", ""))
    p = subprocess.Popen(args, stdout=errf, stderr=errf, env=env)
    for _ in range(180):
        time.sleep(1)
        try:
            if b"ok" in urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2).read():
                return p
        except Exception:
            pass
        if p.poll() is not None:
            break
    p.kill()
    raise SystemExit(f"server with {n_slots} slots did not start (see logs/pr320_np{n_slots}.server.log)")


def ask(slot, messages, n=200):
    body = {"messages": messages, "max_tokens": n, "temperature": 0, "id_slot": slot, "cache_prompt": True,
            "chat_template_kwargs": {"enable_thinking": False}}
    r = json.loads(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions",
                   data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}), timeout=3600).read())
    t = r.get("timings") or {}
    text = r["choices"][0]["message"].get("content") or ""
    acc = (t.get("draft_n_accepted") or 0) / t["draft_n"] if t.get("draft_n") else None
    return text, {"prompt_n": t.get("prompt_n"), "n": t.get("predicted_n"), "tps": round(t.get("predicted_per_second") or 0, 1),
                  "acceptance": None if acc is None else round(acc, 3), "sha": hashlib.sha256(text.encode()).hexdigest()[:12]}


story = ("Write the next part of this story in plain prose, about 150 words. A lighthouse keeper on a small island finds "
         "a sealed glass bottle with a map inside. The map shows the island, but with one more building on the north shore.")
deep = " ".join(f"Entry {i}: the ledger notes {['rain', 'wind', 'fog', 'sun'][i % 4]} at the {['north', 'south', 'east', 'west'][i % 4]} "
                f"station and {i * 7 % 97} visitors." for i in range(a.deep // 18))
deep_msgs = [{"role": "user", "content": deep + "\n\nSummarize the pattern in these entries in five sentences."}]


def conversation(slot, deep_between):
    b1_msgs = [{"role": "user", "content": story}]
    t1, s1 = ask(slot, b1_msgs)
    sa = None
    if deep_between:
        _, sa = ask(0, deep_msgs)
    b2_msgs = b1_msgs + [{"role": "assistant", "content": t1}, {"role": "user", "content": "Continue the story for another 150 words."}]
    _, s2 = ask(slot, b2_msgs)
    return s1, sa, s2


say(f"=== PrismML #320 two-slot check: window {a.window}, deep request about {a.deep} tokens, bin {a.bin}")
p = start(2)
try:
    s1, sa, s2 = conversation(1, True)
finally:
    p.kill(); p.wait()
say(f"two slots: B1 (slot 1) {json.dumps(s1)}")
say(f"two slots: A  (slot 0, deep, alone) {json.dumps(sa)}")
say(f"two slots: B2 (slot 1, after A) {json.dumps(s2)}")
time.sleep(5)
p = start(1)
try:
    r1, _, r2 = conversation(0, False)
finally:
    p.kill(); p.wait()
say(f"one slot:  B1 {json.dumps(r1)}")
say(f"one slot:  B2 {json.dumps(r2)}")
same = s2["sha"] == r2["sha"]
say(f"B2 text same as one slot: {same}; B2 acceptance two slots {s2['acceptance']} vs one slot {r2['acceptance']}; "
    f"B2 prompt tokens evaluated {s2['prompt_n']} vs {r2['prompt_n']}")
