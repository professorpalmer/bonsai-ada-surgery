"""Offline census: how often does the model's written arithmetic in reasoning disagree with the truth?
Parses integer expressions of the form  a (+|-|*) b [(+|-|*) c ...] = r  and checks r."""
import glob, json, re, sys
EXPR = re.compile(r"(?<![\w.])(\d{1,9}(?:\s*[-+*×]\s*\d{1,9}){1,6})\s*=\s*(-?\d{1,12})(?![\d.])")

def check(text):
    ok = bad = 0; bads = []
    for m in EXPR.finditer(text):
        lhs, rhs = m.group(1).replace("×", "*"), int(m.group(2))
        try:
            v = eval(lhs, {"__builtins__": {}})  # digits and + - * only (regex-guarded)
        except Exception:
            continue
        if v == rhs: ok += 1
        else: bad += 1; bads.append(m.group(0))
    return ok, bad, bads

rows = []
for d in ("H2", "H2T", "H2R", "pz-pilot"):
    for p in glob.glob(f"{d}/*.json"):
        r = json.load(open(p, encoding="utf-8"))
        if r.get("status") != "ok": continue
        m = r["response"]["choices"][0]["message"]
        ok, bad, bads = check((m.get("reasoning_content") or "") + "\n" + (m.get("content") or ""))
        rows.append(dict(src=d, kind=r["kind"], seed=r["seed"], arm=r["arm"], correct=r["correct"], ok=ok, bad=bad, ex=bads[:3]))
tot_ok = sum(r["ok"] for r in rows); tot_bad = sum(r["bad"] for r in rows)
print(f"traces {len(rows)}  equations {tot_ok + tot_bad}  wrong {tot_bad} ({100 * tot_bad / max(1, tot_ok + tot_bad):.2f}%)")
for c in (True, False):
    rs = [r for r in rows if r["correct"] == c]
    print(f"final {'correct' if c else 'WRONG  '}: traces {len(rs)}, with >=1 slip {sum(r['bad'] > 0 for r in rs)}, "
          f"slips/trace {sum(r['bad'] for r in rs) / max(1, len(rs)):.2f}")
for k in sorted(set(r["kind"] for r in rows)):
    rs = [r for r in rows if r["kind"] == k]
    print(f"  {k:9s} eq {sum(r['ok'] + r['bad'] for r in rs):6d} wrong {sum(r['bad'] for r in rs):4d}")
print("examples:", [e for r in rows if r["bad"] for e in r["ex"]][:12])
