"""Why does the state after an answer often fail to be a prefix of the next turn? Direct to the inner server (no layer).
Per turn: the generated token ids (return_tokens, verbose), the tokens of the answer text as the next turn renders it,
and the next request's timings.cache_n against the slot size after the answer.

python diag.py BASE KEYFILE DOC_TOKENS TURNS OUT.jsonl
"""
import json
import random
import sys
import urllib.request

BASE, KEY, DEPTH, TURNS, OUT = sys.argv[1], open(sys.argv[2]).read().strip(), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
H = {"Content-Type": "application/json", "Authorization": "Bearer " + KEY}


def post(path, body):
    return json.loads(urllib.request.urlopen(urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers=H),
                                             timeout=7200).read())


def get(path):
    return json.loads(urllib.request.urlopen(urllib.request.Request(BASE + path, headers=H), timeout=60).read())


rng = random.Random(7)
codes = {i: rng.randrange(1000, 9999) for i in range(1, 9)}
filler = " ".join("Note %d: the %s line was checked and logged." % (i, rng.choice(["pump", "valve", "fan", "belt"]))
                  for i in range(DEPTH // 12))
doc = "Facility notes:\n" + filler + "\n" + "\n".join("Vault %d code: %d" % (i, c) for i, c in codes.items()) + "\n"
QS = ["List the access codes of vaults 1 to 8, one per line, as 'vault N: CODE'. Then stop.",
      "Which vault has the largest code? Answer with the vault number and the code only.",
      "What is the sum of the codes of vaults 1, 2 and 3? Give the number only.",
      "Repeat the code of vault 5 and the code of vault 7, nothing else.",
      "Which vaults have a code above 5000? List the vault numbers only."]
msgs = [{"role": "user", "content": doc + QS[0]}]
prev_n = None
with open(OUT, "w", encoding="utf-8") as out:
    for k in range(1, TURNS + 1):
        body = {"messages": msgs, "max_tokens": 160, "temperature": 0, "cache_prompt": True,
                "chat_template_kwargs": {"enable_thinking": False}, "return_tokens": True, "verbose": True}
        r = post("/v1/chat/completions", body)
        ans = r["choices"][0]["message"].get("content") or ""
        gen = (r.get("__verbose") or {}).get("tokens") or []
        t = r.get("timings") or {}
        n_slot = get("/slots")[0].get("n_prompt_tokens")
        # the answer as the next turn renders it: tokens of (history + answer + <|im_end|>) minus tokens of the prompt
        msgs2 = msgs + [{"role": "assistant", "content": ans}]
        p_now = post("/apply-template", {"messages": msgs, "chat_template_kwargs": {"enable_thinking": False}})["prompt"]
        p_next = post("/apply-template", {"messages": msgs2 + [{"role": "user", "content": "x"}],
                                          "chat_template_kwargs": {"enable_thinking": False}})["prompt"]
        tk_now = post("/tokenize", {"content": p_now, "add_special": False, "parse_special": True})["tokens"]
        tk_next = post("/tokenize", {"content": p_next, "add_special": False, "parse_special": True})["tokens"]
        same_prefix = tk_next[:len(tk_now)] == tk_now
        rendered = tk_next[len(tk_now):len(tk_now) + len(gen) + 2]
        first_diff = next((i for i, (a, b) in enumerate(zip(gen, rendered)) if a != b), None)
        rec = {"turn": k, "cache_n": t.get("cache_n"), "prev_slot_n": prev_n, "prompt_n": t.get("prompt_n"),
               "n_prompt": len(tk_now), "n_slot_after": n_slot, "n_gen": len(gen), "prompt_prefix_ok": same_prefix,
               "gen_vs_rendered_first_diff": first_diff, "gen_tail": gen[-4:], "rendered_head": rendered[:len(gen) + 2][-6:],
               "answer": ans, "stop": r["choices"][0].get("finish_reason"),
               "draft_n": t.get("draft_n"), "draft_n_accepted": t.get("draft_n_accepted")}
        out.write(json.dumps(rec) + "\n")
        out.flush()
        print(json.dumps({k2: v for k2, v in rec.items() if k2 != "answer"}), flush=True)
        prev_n = n_slot
        msgs = msgs2 + [{"role": "user", "content": "Tool output: entry %d checked.\n%s" % (k, QS[k % len(QS)])}]
