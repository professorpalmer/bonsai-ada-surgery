"""Grade the soak's answers against the ground truth (vault codes and tool blocks are seeded)."""
import json
import random
import re
import sys

rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
SEED = {"A": 101, "B": 202, "C": 303}


def truth(conv, turn):
    seed = SEED[conv]
    rng = random.Random(seed)
    codes = {i: rng.randrange(1000, 9999) for i in range(1, 9)}
    q = (turn - 1) % 6
    if q == 0:
        return [str(codes[i]) for i in range(1, 5)], "all"
    if q == 1:
        v = max(codes, key=codes.get)
        return [str(v), str(codes[v])], "all"
    if q == 2:
        return [str(codes[1] + codes[2])], "all"
    if q == 3:
        return [str(codes[6])], "all"
    if q == 4:
        return sorted(str(i) for i, c in codes.items() if c < 5000), "set"
    r = random.Random(seed * 1000 + (turn - 1))   # the last tool block is tool(turn - 1)
    return [str(r.randrange(10000, 99999))], "all"


def ok(conv, turn, ans):
    want, mode = truth(conv, turn)
    nums = re.findall(r"\d+", ans)
    if mode == "set":
        got = sorted(set(n for n in nums if len(n) == 1))
        return got == want
    return all(w in nums for w in want)


for arm in ("soak", "ref"):
    score = {c: 0 for c in "ABC"}
    for r in rows:
        if r["arm"] == arm and ok(r["conv"], r["turn"], r["answer"]):
            score[r["conv"]] += 1
    print(arm, score, "total", sum(score.values()), "of 45")
