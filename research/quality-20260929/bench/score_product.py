"""Score a product benchmark (run_product.py output) against its plan's gates: paired RAW vs PROD by
(family, task, seed), rescues/losses per set, tokens per task family."""
import argparse
import collections
import json
import os

GAIN = {"dev-bundle-01", "dev-bundle-02", "xfer-zip-01", "knapsack", "digits", "sales", "weblog"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    seen = {}
    for l in open(os.path.join(a.out, "results.jsonl"), encoding="utf-8"):
        r = json.loads(l)
        seen[tuple(r["key"])] = r          # last record per key wins (reruns)
    by = collections.defaultdict(dict)
    for (fam, name, seed, arm), r in seen.items():
        by[(fam, name, seed)][arm] = r
    sets = {"GAIN": [0, 0, 0, 0], "REGRESSION": [0, 0, 0, 0]}   # raw, prod, rescues, losses
    fams = collections.defaultdict(lambda: [0, 0, 0, 0, 0, 0])  # raw ok, prod ok, n, raw tok, prod tok, infra
    infra = []
    for (fam, name, seed), arms in sorted(by.items()):
        if "RAW" not in arms or "PROD" not in arms:
            continue
        ra, pr = arms["RAW"], arms["PROD"]
        if ra["functional"] is None or pr["functional"] is None:
            infra.append((name, seed, ra["detail"], pr["detail"]))
            fams[name][5] += 1
            continue
        s = sets["GAIN" if name in GAIN else "REGRESSION"]
        s[0] += bool(ra["functional"]); s[1] += bool(pr["functional"])
        s[2] += (pr["functional"] and not ra["functional"]); s[3] += (ra["functional"] and not pr["functional"])
        f = fams[name]
        f[0] += bool(ra["functional"]); f[1] += bool(pr["functional"]); f[2] += 1
        f[3] += ra["tokens"] or 0; f[4] += pr["tokens"] or 0
        mark = "RESCUE" if (pr["functional"] and not ra["functional"]) else "LOSS" if (ra["functional"] and not pr["functional"]) else ""
        print(f"{fam:9s} {name:16s} {seed} RAW {str(bool(ra['functional'])):5s} {ra['tokens']!s:>6} | PROD {str(bool(pr['functional'])):5s} {pr['tokens']!s:>6} {mark}")
    print()
    for k, (r, p, res, los) in sets.items():
        n = sum(1 for (fam, name, seed) in by if (name in GAIN) == (k == "GAIN") and len(by[(fam, name, seed)]) == 2)
        print(f"{k}: RAW {r}/{n} PROD {p}/{n} rescues {res} losses {los} net {res - los}")
    print("gates: gain net >= 4 with losses <= 1 ->", "PASS" if sets["GAIN"][2] - sets["GAIN"][3] >= 4 and sets["GAIN"][3] <= 1 else "FAIL",
          "| regression net >= -1 ->", "PASS" if sets["REGRESSION"][2] - sets["REGRESSION"][3] >= -1 else "FAIL")
    print()
    print(f"{'family':16s} {'raw':>5s} {'prod':>5s} {'n':>3s} {'raw tok':>9s} {'prod tok':>9s} {'ratio':>6s}")
    for name, (r, p, n, rt, pt, inf) in sorted(fams.items()):
        print(f"{name:16s} {r:5d} {p:5d} {n:3d} {rt:9d} {pt:9d} {pt / rt if rt else 0:6.2f}" + (f"  infra {inf}" if inf else ""))
    if infra:
        print("infra:", infra)


if __name__ == "__main__":
    main()
