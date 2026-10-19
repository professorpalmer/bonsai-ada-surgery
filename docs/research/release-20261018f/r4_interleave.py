"""R4 (release-20261018f): two ~20k conversations take turns (A1 B1 A2 B2) through the layer; prints the reply's
cache_n (tokens the server did not read again) per turn.
python r4_interleave.py BASE KEYFILE
"""
import json
import random
import sys
import urllib.request

BASE, KEY = sys.argv[1], open(sys.argv[2]).read().strip()
H = {"Content-Type": "application/json", "Authorization": "Bearer " + KEY}


def doc(tag, seed):
    rng = random.Random(seed)
    return ("Log %s:\n" % tag) + " ".join("Line %d: the %s on bay %d was checked." % (i, rng.choice(["pump", "valve", "fan"]), rng.randint(1, 50))
                                          for i in range(1600)) + "\nThe key of %s is %d.\n" % (tag, rng.randint(1000, 9999))


convs = {"A": [{"role": "user", "content": doc("A", 1) + "What is the key of A? Number only."}],
         "B": [{"role": "user", "content": doc("B", 2) + "What is the key of B? Number only."}]}
for k in (1, 2):
    for tag in "AB":
        body = {"messages": convs[tag], "max_tokens": 24, "temperature": 0, "code_interpreter": False,
                "chat_template_kwargs": {"enable_thinking": False}}
        r = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(),
                                                                     headers=H), timeout=3600).read())
        ans = r["choices"][0]["message"].get("content") or ""
        t = r.get("timings") or {}
        print(json.dumps({"conv": tag, "turn": k, "prompt_n": t.get("prompt_n"), "cache_n": t.get("cache_n"), "answer": ans[:30]}), flush=True)
        convs[tag] = convs[tag] + [{"role": "assistant", "content": ans},
                                   {"role": "user", "content": "Now name the first line's machine. One word."}]
