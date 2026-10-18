"""D1 / D2 of docs/research/delta-saves-20261018: a chain restore (full + 4 deltas) against a full-file restore.
Direct to the server (no layer). Phases (the harness restarts the server between them):
  build  : turn 1 + full save, turns 2-5 + a delta save each (pos_min = the slot size before the turn), a full save of the
           final state, and the next turn's messages -> STATE json
  full   : restore the final full save, ask the next turn
  chain  : restore the first full save, then the 4 deltas with append, ask the next turn
python d1_test.py PHASE BASE KEYFILE SLOTDIR DEPTH STATE.json OUT.jsonl
"""
import json
import os
import random
import sys
import time
import urllib.request

PHASE, BASE, KEY, SLOTS, DEPTH, STATE, OUT = sys.argv[1], sys.argv[2], open(sys.argv[3]).read().strip(), sys.argv[4], int(sys.argv[5]), sys.argv[6], sys.argv[7]
H = {"Content-Type": "application/json", "Authorization": "Bearer " + KEY}
TAG = "d%dk" % (DEPTH // 1000)


def post(path, body, timeout=7200):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers=H)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def n_slot():
    with urllib.request.urlopen(urllib.request.Request(BASE + "/slots", headers=H), timeout=60) as r:
        return json.loads(r.read())[0].get("n_prompt_tokens")


def chat(msgs):
    t0 = time.time()
    r = post("/v1/chat/completions", {"messages": msgs, "max_tokens": 120, "temperature": 0, "cache_prompt": True,
                                      "chat_template_kwargs": {"enable_thinking": False}})
    t = r.get("timings") or {}
    return r["choices"][0]["message"].get("content") or "", t, round(time.time() - t0, 2)


def rec(d):
    d["tag"], d["phase"] = TAG, PHASE
    open(OUT, "a", encoding="utf-8").write(json.dumps(d) + "\n")
    print(json.dumps({k: v for k, v in d.items() if k != "answer"}), flush=True)


def size(name):
    return os.path.getsize(os.path.join(SLOTS, name))


if PHASE == "build":
    rng = random.Random(11)
    codes = {i: rng.randrange(1000, 9999) for i in range(1, 9)}
    filler = " ".join("Note %d: the %s line was checked and logged." % (i, rng.choice(["pump", "valve", "fan", "belt"]))
                      for i in range(DEPTH // 12))
    doc = "Facility notes:\n" + filler + "\n" + "\n".join("Vault %d code: %d" % (i, c) for i, c in codes.items()) + "\n"
    qs = ["List the codes of vaults 1 to 4.", "Which vault has the largest code?", "Sum the codes of vaults 1 and 2.",
          "Repeat the code of vault 6.", "Which vaults have codes below 5000?", "What is the code of vault 8?"]

    def tool(k):
        r = random.Random(100 + k)
        return "Tool output %d:\n" % k + "\n".join("entry %d: %s reading %d" % (r.randrange(10000, 99999), r.choice(["seal", "gauge"]),
                                                                          r.randrange(1, 999)) for _ in range(160)) + "\n"
    msgs = [{"role": "user", "content": doc + qs[0]}]
    files, prev = [], None
    for k in range(5):
        before = n_slot() or 0
        ans, t, wall = chat(msgs)
        n = n_slot()
        name = "d1-%s-%d.bin" % (TAG, k)
        body = {"filename": name}
        if k:
            body["pos_min"] = prev
        t1 = time.time()
        post("/slots/0?action=save", body)
        files.append({"name": name, "pos_min": body.get("pos_min", 0), "n": n, "bytes": size(name), "save_s": round(time.time() - t1, 2)})
        rec({"turn": k + 1, "n_slot": n, "answer": ans, "prompt_n": t.get("prompt_n"), "file": files[-1]})
        prev = n
        msgs = msgs + [{"role": "assistant", "content": ans}, {"role": "user", "content": tool(k) + qs[(k + 1) % len(qs)]}]
    t1 = time.time()
    post("/slots/0?action=save", {"filename": "d1-%s-full.bin" % TAG})
    full = {"name": "d1-%s-full.bin" % TAG, "n": n_slot(), "bytes": size("d1-%s-full.bin" % TAG), "save_s": round(time.time() - t1, 2)}
    json.dump({"msgs": msgs, "files": files, "full": full}, open(STATE, "w", encoding="utf-8"))
    rec({"files": files, "full": full})
else:
    st = json.load(open(STATE, encoding="utf-8"))
    t1 = time.time()
    if PHASE == "full":
        post("/slots/0?action=restore", {"filename": st["full"]["name"]})
    else:
        for i, f in enumerate(st["files"]):
            post("/slots/0?action=restore", {"filename": f["name"], **({"append": True} if i else {})})
    restore_s = round(time.time() - t1, 2)
    n_restored = n_slot()
    ans, t, wall = chat(st["msgs"])
    rec({"n_restored": n_restored, "restore_s": restore_s, "answer": ans, "prompt_n": t.get("prompt_n"),
         "cache_n": t.get("cache_n"), "wall_s": wall})
