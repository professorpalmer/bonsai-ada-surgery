"""One turn of soak conversation CONV (A, B or C) through the layer: a ~30k-token document per conversation, then each
turn adds the previous answer, a ~2.5k-token tool block and a question. Answers of earlier turns come from STATE.
python soak_turn.py BASE KEYFILE CONV TURN STATE.json OUT.jsonl ARM
"""
import json
import os
import random
import sys
import time
import urllib.request

BASE, KEY, CONV, TURN, STATE, OUT, ARM = sys.argv[1], open(sys.argv[2]).read().strip(), sys.argv[3], int(sys.argv[4]), sys.argv[5], sys.argv[6], sys.argv[7]
H = {"Content-Type": "application/json", "Authorization": "Bearer " + KEY}
seed = {"A": 101, "B": 202, "C": 303}[CONV]
rng = random.Random(seed)
codes = {i: rng.randrange(1000, 9999) for i in range(1, 9)}
doc = "Site %s notes:\n" % CONV + " ".join("Note %d: the %s line was checked." % (i, rng.choice(["pump", "valve", "fan", "belt", "seal"]))
                                         for i in range(3000)) + "\n" + "\n".join("Vault %d code: %d" % (i, c) for i, c in codes.items()) + "\n"
QS = ["List the codes of vaults 1 to 4.", "Which vault has the largest code? Number and code only.",
      "Sum the codes of vaults 1 and 2. Number only.", "Repeat the code of vault 6.",
      "Which vaults have codes below 5000? Numbers only.", "In the last tool output, which entry number comes first?"]


def tool(k):
    r = random.Random(seed * 1000 + k)
    return "Tool output %d:\n" % k + "\n".join("entry %d: %s reading %d" % (r.randrange(10000, 99999), r.choice(["seal", "gauge", "pump"]),
                                                                      r.randrange(1, 999)) for _ in range(160)) + "\n"


st = json.load(open(STATE, encoding="utf-8")) if os.path.exists(STATE) else {}
answers = st.get(CONV, [])
msgs = [{"role": "user", "content": doc + QS[0]}]
for k in range(1, TURN):
    msgs += [{"role": "assistant", "content": answers[k - 1]}, {"role": "user", "content": tool(k) + QS[k % len(QS)]}]
body = {"messages": msgs, "max_tokens": 120, "temperature": 0, "code_interpreter": False,
        "chat_template_kwargs": {"enable_thinking": False}}
t0 = time.time()
r = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(), headers=H),
                                      timeout=3600).read())
ans = r["choices"][0]["message"].get("content") or ""
t = r.get("timings") or {}
st[CONV] = answers[:TURN - 1] + [ans]
json.dump(st, open(STATE, "w", encoding="utf-8"))
rec = {"arm": ARM, "conv": CONV, "turn": TURN, "wall_s": round(time.time() - t0, 2), "prompt_n": t.get("prompt_n"),
       "cache_n": t.get("cache_n"), "answer": ans}
open(OUT, "a", encoding="utf-8").write(json.dumps(rec) + "\n")
print(json.dumps({k: v for k, v in rec.items() if k != "answer"}), flush=True)
