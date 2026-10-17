"""P162 driver: read ahead (PR #159) through the layer on :8081.
phase readahead: [user: document] with "prefill_only": true.
phase ask:       [user: document], [user: question] (the question is a NEW message, so it extends the saved state).
"""
import argparse, json, os, sys, time, urllib.request
sys.path.insert(0, r"C:\bonsai\8gb\benchx")
os.environ.setdefault("BONSAI_REPO", r"C:\bonsai\bonsai-ada-surgery")
import t1b_slot  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--key-file", required=True)
ap.add_argument("--depth", type=int, required=True)
ap.add_argument("--phase", choices=["readahead", "ask"], required=True)
ap.add_argument("--tag", default="")
ap.add_argument("--out", required=True)
a = ap.parse_args()
key = open(a.key_file).read().strip()
doc = t1b_slot.document("http://127.0.0.1:8080", key, a.depth)
msgs = [{"role": "user", "content": doc}]
body = {"messages": msgs, "max_tokens": 64, "temperature": 0, "stream": True, "code_interpreter": False,
        "chat_template_kwargs": {"enable_thinking": False}}
if a.phase == "readahead":
    body["prefill_only"] = True
else:
    body["messages"] = msgs + [{"role": "user", "content": t1b_slot.Q1}]
req = urllib.request.Request("http://127.0.0.1:8081/v1/chat/completions", data=json.dumps(body).encode(),
                             headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
t0 = time.time()
rec = {"tag": a.tag, "phase": a.phase, "depth": a.depth}
try:
    r = urllib.request.urlopen(req, timeout=10800)
    raw = r.read()
    rec["wall_s"] = round(time.time() - t0, 2)
    if a.phase == "readahead":
        rec["result"] = json.loads(raw)
    else:
        text, timings = "", {}
        for line in raw.decode("utf-8", "replace").splitlines():
            if line.startswith("data: ") and line[6:].strip() not in ("", "[DONE]"):
                ev = json.loads(line[6:])
                if "error" in ev:
                    rec["error"] = ev["error"]
                for ch in ev.get("choices") or []:
                    text += (ch.get("delta") or {}).get("content") or ""
                timings = ev.get("timings") or timings
        rec.update(answer=text, prompt_n=timings.get("prompt_n"), prompt_ms=timings.get("prompt_ms"))
except Exception as e:  # noqa: BLE001
    rec["error"] = repr(e)[:300]
    rec["wall_s"] = round(time.time() - t0, 2)
print(json.dumps(rec), flush=True)
with open(a.out, "a", encoding="utf-8") as f:
    f.write(json.dumps(rec) + "\n")
