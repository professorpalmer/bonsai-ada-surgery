"""R2 / R3 of docs/research/gdn-replay-20261018: greedy and seeded outputs, text hash + draft counts per request.
python r2.py BASE KEYFILE DEPTH OUT.jsonl TAG
"""
import hashlib
import json
import random
import sys
import time
import urllib.request

BASE, KEY, DEPTH, OUT, TAG = sys.argv[1], open(sys.argv[2]).read().strip(), int(sys.argv[3]), sys.argv[4], sys.argv[5]
H = {"Content-Type": "application/json", "Authorization": "Bearer " + KEY}
rng = random.Random(11)
filler = " ".join("Record %d: the %s on line %d read %d units at %02d:%02d." % (
    i, rng.choice(["pump", "valve", "fan", "belt", "gauge"]), rng.randint(1, 40), rng.randint(100, 999), rng.randint(0, 23),
    rng.randint(0, 59)) for i in range(max(1, DEPTH // 22)))
prompts = {
    "story": filler + "\n\nIgnore the records above. Write a detailed story (about 500 words) about a ferry pilot in fog.",
    "code": filler + "\n\nIgnore the records above. Write a complete Python module with a min-heap priority queue class "
            "(push, pop, peek, update_priority, __len__) with docstrings and a self-test.",
    "quote": filler + "\n\nList every record above that mentions a valve on line 7, copying each record exactly.",
}
for name, text in prompts.items():
    for temp, seed in ((0.0, 1), (0.8, 5)):
        body = {"messages": [{"role": "user", "content": text}], "max_tokens": 300, "temperature": temp, "seed": seed,
                "top_p": 0.95 if temp else 1.0, "chat_template_kwargs": {"enable_thinking": False}, "cache_prompt": False}
        t0 = time.time()
        r = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(),
                                                                     headers=H), timeout=3600).read())
        t = r.get("timings") or {}
        txt = r["choices"][0]["message"].get("content") or ""
        rec = {"tag": TAG, "depth": DEPTH, "prompt": name, "temp": temp, "sha": hashlib.sha1(txt.encode()).hexdigest()[:16],
               "n": t.get("predicted_n"), "tg": t.get("predicted_per_second"), "draft_n": t.get("draft_n"),
               "draft_acc": t.get("draft_n_accepted"), "wall": round(time.time() - t0, 1), "head": txt[:80]}
        open(OUT, "a", encoding="utf-8").write(json.dumps(rec) + "\n")
        print(json.dumps(rec), flush=True)
