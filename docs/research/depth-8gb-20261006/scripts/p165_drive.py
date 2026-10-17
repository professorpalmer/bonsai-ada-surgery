"""P165 driver: the demo clip on the shipped bundle, through the layer on :8081, streamed, with first-token timing.
phase readahead: [user: document] with "prefill_only": true.
phase ask N:     [user: document], then N questions so far (each a new user message, the earlier answers as assistant turns).
"""
import argparse, json, os, sys, time, urllib.request
sys.path.insert(0, r"C:\bonsai\8gb\benchx")
os.environ.setdefault("BONSAI_REPO", r"C:\bonsai\bonsai-ada-surgery")
import t1b_slot  # noqa: E402

QS = ["List the access codes of vaults 1 to 8, one per line, as 'vault N: CODE'. Then stop.",
      "Which vault has the largest code? Answer with the vault number and the code only.",
      "What is the code of vault 3? Give the number only."]
ap = argparse.ArgumentParser()
ap.add_argument("--key-file", required=True)
ap.add_argument("--depth", type=int, required=True)
ap.add_argument("--phase", choices=["readahead", "ask"], required=True)
ap.add_argument("--n", type=int, default=1)
ap.add_argument("--state", required=True)
ap.add_argument("--tag", default="")
ap.add_argument("--out", required=True)
a = ap.parse_args()
key = open(a.key_file).read().strip()
doc = t1b_slot.document("http://127.0.0.1:8080", key, a.depth)
st = json.load(open(a.state, encoding="utf-8")) if os.path.exists(a.state) else {"answers": []}
msgs = [{"role": "user", "content": doc}]
body = {"max_tokens": 200, "temperature": 0, "stream": True, "code_interpreter": False,
        "chat_template_kwargs": {"enable_thinking": False}}
if a.phase == "readahead":
    body.update(messages=msgs, prefill_only=True)
else:
    for k in range(a.n):
        msgs.append({"role": "user", "content": QS[k]})
        if k < a.n - 1:
            msgs.append({"role": "assistant", "content": st["answers"][k]})
    body["messages"] = msgs
req = urllib.request.Request("http://127.0.0.1:8081/v1/chat/completions", data=json.dumps(body).encode(),
                             headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
rec = {"tag": a.tag, "phase": a.phase, "depth": a.depth, "n": a.n}
t0 = time.time()
first = None
text, timings, result = "", {}, None
try:
    r = urllib.request.urlopen(req, timeout=10800)
    for raw in r:
        line = raw.decode("utf-8", "replace").strip()
        if not line.startswith("data: ") or line[6:] in ("", "[DONE]"):
            continue
        ev = json.loads(line[6:])
        if ev.get("prefill_only"):
            result = ev
        for ch in ev.get("choices") or []:
            c = (ch.get("delta") or {}).get("content") or ""
            if c and first is None:
                first = time.time() - t0
            text += c
        timings = ev.get("timings") or timings
    rec.update(wall_s=round(time.time() - t0, 2), first_token_s=round(first, 2) if first else None, answer=text,
               prompt_n=timings.get("prompt_n"), tg=timings.get("predicted_per_second"),
               slot_cache=(result or {}).get("slot_cache"))
    if a.phase == "ask":
        st["answers"] = st["answers"][:a.n - 1] + [text]
        json.dump(st, open(a.state, "w", encoding="utf-8"))
except Exception as e:  # noqa: BLE001
    rec.update(error=repr(e)[:300], wall_s=round(time.time() - t0, 2))
print(json.dumps(rec), flush=True)
with open(a.out, "a", encoding="utf-8") as f:
    f.write(json.dumps(rec) + "\n")
