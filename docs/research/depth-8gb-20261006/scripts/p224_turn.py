"""P224 driver (copy of the P155 driver; adds --short and the true codes): one turn of a long agent-like conversation through the layer (:8081), for the T1-c gates.

The conversation: a facility document of --depth tokens (the 4070's t1b_slot.document, 8 vault codes) + Q1; each later turn
appends the previous answer (assistant), a ~2.5k-token "tool output" block and the next question. Answers of earlier
turns come from --state (this arm's own answers), so two arms only have the same history if their answers agree.
--edit: change one word in the first user message (the rollback case: the history differs before the saved end).

python p155_turn.py --key-file F --depth 131072 --turn 3 --arm R --state s.json --out o.jsonl [--think] [--edit]
"""
import argparse
import json
import os
import random
import re
import sys
import time
import urllib.request

sys.path.insert(0, r"C:\bonsai\8gb\benchx")
os.environ.setdefault("BONSAI_REPO", r"C:\bonsai\bonsai-ada-surgery")
import t1b_slot  # noqa: E402

QS = ["List the access codes of vaults 1 to 8, one per line, as 'vault N: CODE'. Then stop.",
      "Which vault has the largest code? Answer with the vault number and the code only.",
      "What is the sum of the codes of vaults 1, 2 and 3? Give the number only.",
      "Repeat the code of vault 5 and the code of vault 7, nothing else.",
      "Which vaults have a code above 5000? List the vault numbers only.",
      "In the last tool output, which entry number is mentioned first? Give the number only."]


def tool_block(turn):
    rng = random.Random(1000 + turn)
    words = ["pump", "valve", "sensor", "relay", "fan", "belt", "gauge", "filter", "motor", "seal"]
    lines = [f"entry {rng.randrange(10000, 99999)}: {rng.choice(words)} {rng.choice(words)} checked, reading {rng.randrange(1, 999)}"
             for _ in range(220)]
    return "Tool output (maintenance log):\n" + "\n".join(lines) + "\n\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8081")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--depth", type=int, required=True)
    ap.add_argument("--turn", type=int, required=True)
    ap.add_argument("--arm", required=True)
    ap.add_argument("--state", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--think", action="store_true")
    ap.add_argument("--edit", action="store_true")
    ap.add_argument("--short", default="", help="comma list of turns whose user message has no tool block (the short turns)")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    doc = t1b_slot.document("http://127.0.0.1:8080", key, a.depth)   # tokenizer only: the inner server
    if a.edit:
        doc = doc.replace("Facility notes:", "Facility records:", 1)
    st = json.load(open(a.state, encoding="utf-8")) if os.path.exists(a.state) else {"answers": []}
    msgs = [{"role": "user", "content": doc + QS[0]}]
    for k in range(1, a.turn):
        msgs.append({"role": "assistant", "content": st["answers"][k - 1]})
        short = str(k + 1) in a.short.split(",")
        msgs.append({"role": "user", "content": ("" if short else tool_block(k)) + QS[k % len(QS)]})
    body = {"messages": msgs, "max_tokens": 1024 if a.think else 160, "temperature": 0, "cache_prompt": True,
            "code_interpreter": False, "chat_template_kwargs": {"enable_thinking": bool(a.think)}}
    req = urllib.request.Request(a.base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(req, timeout=10800).read())
    wall = time.time() - t0
    ans = r["choices"][0]["message"].get("content") or ""
    t = r.get("timings", {})
    if not a.edit:
        st["answers"] = st["answers"][:a.turn - 1] + [ans]
        json.dump(st, open(a.state, "w", encoding="utf-8"))
    rec = {"arm": a.arm, "turn": a.turn, "depth": a.depth, "think": a.think, "edit": a.edit, "wall_s": round(wall, 2),
           "prompt_n": t.get("prompt_n"), "prompt_ms": t.get("prompt_ms"), "predicted_n": t.get("predicted_n"),
           "tg": t.get("predicted_per_second"), "answer": ans,
           "codes": {m.group(1): m.group(2) for m in re.finditer(r"access code for vault (\d) is (\d+)\.", doc)}, "layer": r.get("layer")}
    with open(a.out, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")
    print(json.dumps({k: v for k, v in rec.items() if k not in ("answer", "codes")}), flush=True)


if __name__ == "__main__":
    main()
