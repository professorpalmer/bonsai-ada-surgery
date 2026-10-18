"""P189 drift score: compare the answer-token distributions of an arm with a base arm (window off), item by item.

For each item, walk the generated tokens while the base and the arm chose the same token. At each such step, compute
KL(base || arm) over the base's top-20 tokens (a token missing from the arm's top-20 gets the arm's 20th log-prob; the
mass outside the top-20 is one more bucket). The item score is the max KL over the shared steps; the first step where the
two arms choose different tokens counts as a change.

python p189_drift.py BASE_PREFIX ARM_PREFIX [ARM_PREFIX ...]   (prefix + "_code.jsonl" / "_prose.jsonl")
"""
import json, math, sys


def load(path):
    return {r["item"]: r for r in map(json.loads, open(path, encoding="utf-8"))}


def dist(top):
    d = {t: lp for t, lp in top}
    rest = 1.0 - sum(math.exp(lp) for lp in d.values())
    return d, max(rest, 1e-9)


def kl(btop, atop):
    bd, brest = dist(btop)
    ad, arest = dist(atop)
    floor = min(ad.values()) if ad else -30.0
    k = 0.0
    for t, lp in bd.items():
        k += math.exp(lp) * (lp - ad.get(t, floor))
    k += brest * (math.log(brest) - math.log(arest))
    return max(k, 0.0)


def score(base, arm):
    out = {}
    for i, b in base.items():
        a = arm.get(i)
        if not a or "lp" not in a or "lp" not in b:
            continue
        mx, step, changed = 0.0, 0, False
        for bt, at in zip(b["lp"], a["lp"]):
            mx = max(mx, kl(bt[2], at[2]))
            step += 1
            if bt[0] != at[0]:
                changed = True
                break
        out[i] = (mx, changed, b["ok"], a["ok"])
    return out


base_prefix = sys.argv[1]
for arm_prefix in sys.argv[2:]:
    tot = []
    line = []
    for s in ("code", "prose"):
        r = score(load(f"{base_prefix}_{s}.jsonl"), load(f"{arm_prefix}_{s}.jsonl"))
        v = sorted(x[0] for x in r.values())
        tot += v
        ch = sum(x[1] for x in r.values())
        cw = sum(1 for x in r.values() if x[2] and not x[3])
        line.append(f"{s}: median {v[len(v) // 2]:.4f} mean {sum(v) / len(v):.4f} changed {ch} lost {cw}")
    tot.sort()
    print(f"{arm_prefix}: all median {tot[len(tot) // 2]:.4f} mean {sum(tot) / len(tot):.4f} p90 {tot[int(len(tot) * 0.9)]:.4f} | " + " | ".join(line))
