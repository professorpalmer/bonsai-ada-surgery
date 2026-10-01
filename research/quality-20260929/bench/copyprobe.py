"""H4 probe: exact recall/copy of numbers from context, as a function of distance, under a given server config.

Each item: a table of labelled 6-digit numbers, optional filler after it (distance), then a request to copy
K named values in order. Thinking off (enable_thinking=false) and temperature 0, so the measurement is the
retrieval itself, not sampling. Graded exactly per value. Host-only data; nothing is executed.
"""
import json
import os
import random
import sys
import time

from run import post

FILLER_WORDS = ("the ledger was reconciled after the quarterly review and every branch reported its totals "
                "on time while the auditors sampled invoices from each region").split()


def item(seed, rows, filler_words, k):
    rng = random.Random(seed)
    labels = [f"{rng.choice('BCDFGHJKLMNPRSTVWXZ')}{rng.choice('AEIOU')}{rng.choice('BCDFGHJKLMNPRSTVWXZ')}-{i:03d}"
              for i in range(rows)]
    vals = [f"{rng.randint(100000, 999999)}" for _ in range(rows)]
    table = "\n".join(f"{l}: {v}" for l, v in zip(labels, vals))
    filler = " ".join(rng.choice(FILLER_WORDS) for _ in range(filler_words))
    pick = rng.sample(range(rows), k)
    q = (f"Reference table:\n{table}\n\nNotes: {filler}\n\nCopy the values of these labels from the reference "
         f"table, in this order, one per line as LABEL: VALUE, and nothing else:\n" +
         "\n".join(labels[i] for i in pick))
    return q, [(labels[i], vals[i]) for i in pick]


def grade(text, want):
    got = {}
    for line in text.splitlines():
        if ":" in line:
            a, b = line.split(":", 1)
            got[a.strip().strip("*` ")] = b.strip().strip("*` ")
    return sum(1 for l, v in want if got.get(l) == v)


def main(tag, out_dir, n_items=12, rows=200, k=20):
    os.makedirs(out_dir, exist_ok=True)
    res = []
    for dist in (0, 4000, 16000):
        for s in range(n_items):
            q, want = item(1000 + s, rows, dist, k)
            body = dict(model="bonsai-2-27b", messages=[{"role": "user", "content": q}], temperature=0.0,
                        max_tokens=1024, chat_template_kwargs={"enable_thinking": False}, cache_prompt=False,
                        seed=1)
            t0 = time.time()
            r = post("/v1/chat/completions", body, 900)
            txt = r["choices"][0]["message"].get("content") or ""
            n = grade(txt, want)
            rec = dict(tag=tag, dist=dist, item=s, correct=n, k=k, prompt_tokens=r["usage"]["prompt_tokens"],
                       wall=round(time.time() - t0, 1), text=txt, want=want)
            res.append(rec)
            print(json.dumps({x: rec[x] for x in ("tag", "dist", "item", "correct", "k", "prompt_tokens")}), flush=True)
    json.dump(res, open(os.path.join(out_dir, f"{tag}.json"), "w", encoding="utf-8"), ensure_ascii=False)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
