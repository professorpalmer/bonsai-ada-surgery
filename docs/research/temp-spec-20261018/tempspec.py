"""Decode speed and draft acceptance against temperature (direct to the server).
python tempspec.py BASE KEYFILE DEPTH OUT.jsonl TAG
"""
import json
import random
import sys
import time
import urllib.request

BASE, KEY, DEPTH, OUT, TAG = sys.argv[1], open(sys.argv[2]).read().strip(), int(sys.argv[3]), sys.argv[4], sys.argv[5]
H = {"Content-Type": "application/json", "Authorization": "Bearer " + KEY}
rng = random.Random(9)
filler = " ".join("Note %d: the %s line was checked and logged by the night shift." % (i, rng.choice(["pump", "valve", "fan", "belt"]))
                  for i in range(max(1, DEPTH // 14)))
prompts = {
    "story": filler + "\n\nIgnore the notes above. Write a long, detailed story (about 600 words) about a lighthouse keeper who finds a map.",
    "code": filler + "\n\nIgnore the notes above. Write a complete Python module that implements an LRU cache class with get, put, "
            "delete, resize and a __repr__, with docstrings and a small self-test at the end.",
}
for name, text in prompts.items():
    for temp in (0.0, 0.7, 1.0):
        for seed in (1, 2, 3):
            if temp == 0.0 and seed > 1:
                continue
            body = {"messages": [{"role": "user", "content": text}], "max_tokens": 400, "temperature": temp, "seed": seed,
                    "top_p": 0.95 if temp else 1.0, "chat_template_kwargs": {"enable_thinking": False}, "cache_prompt": True}
            t0 = time.time()
            r = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(),
                                                                         headers=H), timeout=3600).read())
            t = r.get("timings") or {}
            rec = {"tag": TAG, "depth": DEPTH, "prompt": name, "temp": temp, "seed": seed, "predicted_n": t.get("predicted_n"),
                   "tg": t.get("predicted_per_second"), "draft_n": t.get("draft_n"), "draft_acc": t.get("draft_n_accepted"),
                   "wall": round(time.time() - t0, 1)}
            open(OUT, "a", encoding="utf-8").write(json.dumps(rec) + "\n")
            print(json.dumps(rec), flush=True)
