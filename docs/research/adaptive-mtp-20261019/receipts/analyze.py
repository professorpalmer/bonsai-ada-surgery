import json, sys, collections
recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
arms = sorted({r["tag"] for r in recs}, key=lambda t: ["F1", "F2", "A4", "A3"].index(t) if t in ["F1","F2","A4","A3"] else 9)
by = collections.defaultdict(list)
for r in recs:
    by[(r["tag"], r["prompt"], r["depth"])].append(r)
print("n records", collections.Counter(r["tag"] for r in recs))
for p in ("code", "story", "quote"):
    print("\n==", p, "(mean of T0 and T0.8 tg tok/s; acc% = draft_acc/draft_n)")
    print("depth  " + "  ".join(f"{a:>16}" for a in arms))
    for d in (4000, 32000, 64000, 128000):
        cells = []
        for a in arms:
            rs = by[(a, p, d)]
            if not rs: cells.append(" " * 16); continue
            tg = sum(r["tg"] for r in rs) / len(rs)
            acc = sum(r["draft_acc"] for r in rs) / max(1, sum(r["draft_n"] for r in rs))
            cells.append(f"{tg:7.1f} ({acc*100:3.0f}%)  ")
        print(f"{d:6d} " + "  ".join(f"{c:>16}" for c in cells))
    allm = {a: [r["tg"] for r in recs if r["tag"] == a and r["prompt"] == p] for a in arms}
    base = sum(allm["F1"]) / len(allm["F1"])
    print("all depths: " + ", ".join(f"{a} {sum(v)/len(v):.1f} ({(sum(v)/len(v)/base-1)*100:+.1f} %)" for a, v in allm.items() if v))
# G2: story mean per depth vs F1
print("\nG2 story per depth vs F1:")
for a in arms:
    if a == "F1": continue
    worst = min(((sum(r["tg"] for r in by[(a,"story",d)])/len(by[(a,"story",d)])) / (sum(r["tg"] for r in by[("F1","story",d)])/len(by[("F1","story",d)])) - 1, d) for d in (4000,32000,64000,128000) if by[(a,"story",d)])
    print(f"  {a}: worst {worst[0]*100:+.1f} % at {worst[1]}")
# identity: greedy sha same as F1?
print("\ngreedy text equal to F1 (T0):")
for a in arms:
    if a == "F1": continue
    same = sum(1 for (t,p,d), rs in by.items() if t == a for r in rs if r["temp"] == 0 and any(f["sha"] == r["sha"] for f in by[("F1",p,d)] if f["temp"] == 0))
    tot = sum(1 for r in recs if r["tag"] == a and r["temp"] == 0)
    print(f"  {a}: {same}/{tot}")
