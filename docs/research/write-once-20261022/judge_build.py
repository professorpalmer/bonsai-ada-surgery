"""Build the blind judge files: for each arm (P, C) and seed, two files of 10 pairs (the arm's text as A, then M's text as
A). A file names no arm, only the request and Text A / Text B. python judge_build.py OUTDIR"""
import json
import os
import sys

OUT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
PROMPTS = json.load(open(os.path.join(HERE, "prompts.json"), encoding="utf-8"))
os.makedirs(os.path.join(OUT, "judge"), exist_ok=True)


def text(pid, seed, arm):
    p = os.path.join(OUT, "texts", f"{pid}_s{seed}_{arm}.md")
    if not os.path.exists(p):
        return None
    return open(p, encoding="utf-8").read().split("## final text\n\n", 1)[1].strip()


index = []
for arm in ("P", "C"):
    for seed in (5, 6, 7):
        for order in ("arm_first", "M_first"):
            parts, keys = [], []
            for n, p in enumerate(PROMPTS, 1):
                x, m = text(p["id"], seed, arm), text(p["id"], seed, "M")
                if x is None or m is None:
                    continue
                a, b = (x, m) if order == "arm_first" else (m, x)
                parts.append(f"=== PAIR {n} ===\nREQUEST: {p['text']}\n\n--- TEXT A ---\n{a}\n\n--- TEXT B ---\n{b}\n")
                keys.append({"pair": n, "prompt": p["id"]})
            name = f"judge_{arm}_s{seed}_{order}.txt"
            open(os.path.join(OUT, "judge", name), "w", encoding="utf-8").write("\n".join(parts))
            index.append({"file": name, "arm": arm, "seed": seed, "order": order, "pairs": keys})
json.dump(index, open(os.path.join(OUT, "judge", "index.json"), "w", encoding="utf-8"), indent=1)
print(len(index), "files")
