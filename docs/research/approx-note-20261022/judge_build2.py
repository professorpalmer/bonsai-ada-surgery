"""Blind judge files: arm X against M, one file per seed and order, no arm names.
python judge_build2.py ARM_TEXTS_DIR ARM M_TEXTS_DIR OUTDIR SEEDS PROMPT_IDS   (comma lists)"""
import json
import os
import sys

ARM_DIR, ARM, M_DIR, OUT, SEEDS, PIDS = sys.argv[1:7]
SEEDS = [int(s) for s in SEEDS.split(",")]
PIDS = PIDS.split(",")
HERE = os.path.dirname(os.path.abspath(__file__))
TEXTS = {p["id"]: p["text"] for p in json.load(open(os.path.join(HERE, "prompts.json"), encoding="utf-8"))}
os.makedirs(OUT, exist_ok=True)


def final(d, pid, seed, arm):
    return open(os.path.join(d, f"{pid}_s{seed}_{arm}.md"), encoding="utf-8").read().split("## final text\n\n", 1)[1].strip()


index = []
for seed in SEEDS:
    for order in ("arm_first", "M_first"):
        parts, keys = [], []
        for n, pid in enumerate(PIDS, 1):
            x, m = final(ARM_DIR, pid, seed, ARM), final(M_DIR, pid, seed, "M")
            a, b = (x, m) if order == "arm_first" else (m, x)
            parts.append(f"=== PAIR {n} ===\nREQUEST: {TEXTS[pid]}\n\n--- TEXT A ---\n{a}\n\n--- TEXT B ---\n{b}\n")
            keys.append({"pair": n, "prompt": pid})
        name = f"judge_{ARM}_s{seed}_{order}.txt"
        open(os.path.join(OUT, name), "w", encoding="utf-8").write("\n".join(parts))
        index.append({"file": name, "arm": ARM, "seed": seed, "order": order, "pairs": keys})
json.dump(index, open(os.path.join(OUT, f"index_{ARM}.json"), "w", encoding="utf-8"), indent=1)
print(len(index), "files")
