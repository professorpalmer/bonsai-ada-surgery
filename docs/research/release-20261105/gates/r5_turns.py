"""R5 (release-20261018): 3 turns through the layer with a slot folder; prints the slot-file count after each turn.
Turn 1: a ~20k-token document; turns 2 and 3 add ~5,000 tokens each (more than 4096, less than 8192).

python r5_turns.py BASE KEYFILE SLOTDIR
"""
import glob
import json
import os
import random
import sys
import time
import urllib.request

BASE, KEY, SLOTS = sys.argv[1], open(sys.argv[2]).read().strip(), sys.argv[3]
H = {"Content-Type": "application/json", "Authorization": "Bearer " + KEY}
rng = random.Random(3)
doc = "Facility notes:\n" + " ".join("Note %d: the %s line was checked." % (i, rng.choice(["pump", "valve", "fan"]))
                                     for i in range(1700)) + "\nVault 1 code: 4821\n"


def block(k):
    r = random.Random(k)
    return "Tool output:\n" + "\n".join("entry %d: %s checked, reading %d" % (r.randrange(10000, 99999), r.choice(["belt", "seal", "gauge"]),
                                                                       r.randrange(1, 999)) for _ in range(420)) + "\n"


msgs = [{"role": "user", "content": doc + "What is the code of vault 1? Number only."}]
for k in range(1, 4):
    body = {"messages": msgs, "max_tokens": 40, "temperature": 0, "code_interpreter": False,
            "chat_template_kwargs": {"enable_thinking": False}}
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(),
                                                                 headers=H), timeout=3600).read())
    ans = r["choices"][0]["message"].get("content") or ""
    for _ in range(120):
        st = json.loads(urllib.request.urlopen(BASE + "/layer/slot-cache", timeout=10).read())
        if not st.get("busy"):
            break
        time.sleep(1)
    files = len(glob.glob(os.path.join(SLOTS, "lc-*.bin")))
    print(json.dumps({"turn": k, "s": round(time.time() - t0, 1), "prompt_tokens": (r.get("usage") or {}).get("prompt_tokens"),
                      "slot_files": files, "answer": ans[:40]}), flush=True)
    msgs = msgs + [{"role": "assistant", "content": ans}, {"role": "user", "content": block(k) + "Which entry is first? Number only."}]
