"""Summarize cells.jsonl + texts.jsonl: per cell and prompt, mean decode, prefill (first request), accept rate,
mean accepted per draft step, VRAM, and the greedy text compared with arm a at the same depth.

python summarize.py cells.jsonl texts.jsonl > table.md
"""
import json
import sys
from collections import defaultdict

cells = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
texts = defaultdict(list)
for l in open(sys.argv[2], encoding="utf-8"):
    t = json.loads(l)
    texts[(t["cell"], t["prompt"])].append(t["text"])


def first_diff(a, b):
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return i
    return None if len(a) == len(b) else n


print("| arm | depth | prompt | decode tok/s | vs b | vs bt | prefill tok/s | drafted | accepted | accept % | VRAM after load MiB | text vs a |")
print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
by = {(c["arm"], c["depth"]): c for c in cells}
rows = []
for c in cells:
    for p, reps in c.get("results", {}).items():
        dec = [r["decode_tps"] for r in reps if r.get("decode_tps")]
        if not dec:
            continue
        d = sum(dec) / len(dec)
        vss = []
        for ref in ("b", "bt"):
            bref = by.get((ref, c["depth"]))
            vs = ""
            if bref and c["arm"] != ref:
                bd = [r["decode_tps"] for r in bref["results"][p] if r.get("decode_tps")]
                vs = f"{(d / (sum(bd) / len(bd)) - 1) * 100:+.1f} %"
            vss.append(vs)
        vs = " | ".join(vss)
        r0 = reps[0]
        dn, da = r0.get("draft_n"), r0.get("draft_accepted")
        acc = f"{100 * da / dn:.0f}" if dn else ""
        a_txt = texts.get((f"a_d{c['depth']}", p), [""])[0]
        my = texts.get((c["cell"], p), [""])[0]
        fd = first_diff(a_txt, my)
        cmp = "same" if fd is None else f"differs at char {fd} of {len(a_txt)}"
        if c["arm"] == "a":
            cmp = "(reference)"
        print(f"| {c['arm']} | {c['depth']} | {p} | {d:.1f} | {vs} | {r0.get('prefill_tps', 0):.0f} | {dn or ''} | {da or ''} | {acc} | "
              f"{c.get('mem_loaded_mib', '') - c.get('baseline_mib', 0)} | {cmp} |")
print()
print("memory clocks while busy:", sorted({x for c in cells for x in c.get("mem_clock_busy", [])}))
