"""P226 (#233) gates from runs.jsonl: G1 time, G3 length, G4 health (without the CUDA count), G5 budget. G2 = blind judges (4070).
python p226_gates.py runs.jsonl"""
import json
import statistics
import sys

rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
err = [r for r in rows if "error" in r]
ok = [r for r in rows if "error" not in r]
by = {(r["prompt"], r["seed"], r["arm"]): r for r in ok}
cells = sorted({(r["prompt"], r["seed"]) for r in ok})
print(f"rows {len(rows)} (errors {len(err)})")
for r in err:
    print("  ERROR", r)

print("\ncell                     M wall   A2 wall  ratio | M think / A2 think words | M num / A2 num | words M / A2 / asked | closes M A2")
tm = ta = 0.0
worst = 0.0
for c in cells:
    m, a = by.get(c + ("M",)), by.get(c + ("A2",))
    if not (m and a):
        print(" ", c, "missing arm")
        continue
    tm += m["wall_s"]; ta += a["wall_s"]
    q = a["wall_s"] / m["wall_s"]
    worst = max(worst, q)
    print(f"{c[0]+' s'+str(c[1]):24} {m['wall_s']:7.1f} {a['wall_s']:8.1f} {q:6.2f} | {m['thinking_words']:6} / {a['thinking_words']:6} | "
          f"{m['numbered_words']:5} / {a['numbered_words']:5} | {m['words']:5} / {a['words']:5} / {a['requested_words']} | "
          f"{int(m['budget_closed'])} {int(a['budget_closed'])}")

a2 = [r for r in ok if r["arm"] == "A2"]
mm = [r for r in ok if r["arm"] == "M"]
g1 = ta <= 0.7 * tm and worst <= 1.5
print(f"\nG1 time: A2 total {ta:.1f} s vs M {tm:.1f} s = {ta / tm:.3f}x (<= 0.7); worst cell {worst:.2f}x (<= 1.5): {'PASS' if g1 else 'FAIL'}")

ratios = [r["words"] / r["requested_words"] for r in a2 if r.get("requested_words")]
med = statistics.median(ratios) if ratios else float("nan")
g3 = 0.8 <= med <= 1.3 and max(ratios) <= 2.0
print(f"G3 length (A2): median words/asked {med:.2f} (0.8-1.3); max {max(ratios):.2f} (<= 2.0): {'PASS' if g3 else 'FAIL'}")
mr = [r["words"] / r["requested_words"] for r in mm if r.get("requested_words")]
print(f"   (M for reference: median {statistics.median(mr):.2f}, max {max(mr):.2f})")

def health(arm_rows, name):
    empty = sum(r["empty"] for r in arm_rows)
    wf = [r for r in arm_rows if r["tools_prompt"]]
    wf_ok = sum(r["via_write_file"] for r in wf)
    claims = sum(r["claims_save"] for r in arm_rows)
    leaks = sum(r["count_leak"] for r in arm_rows)
    cut = sum(r["finish"] == "length" for r in arm_rows)
    print(f"   {name}: empty {empty}; write_file {wf_ok}/{len(wf)}; false save claims {claims}; counts in answer {leaks}; cut at cap {cut}")
    return empty == 0 and wf_ok == len(wf) and claims == 0 and leaks == 0 and cut == 0

print("G4 health (CUDA errors: from the server log):")
g4 = health(a2, "A2")
health(mm, "M (reference)")
print(f"   A2: {'PASS' if g4 else 'FAIL'} (before the CUDA count)")
cm, ca = sum(r["budget_closed"] for r in mm), sum(r["budget_closed"] for r in a2)
print(f"G5 budget: A2 closes {ca} vs M {cm}: {'PASS' if ca <= cm else 'FAIL'}")
print(f"\nmedian thinking words M {statistics.median(r['thinking_words'] for r in mm)} / A2 {statistics.median(r['thinking_words'] for r in a2)}; "
      f"median numbered words M {statistics.median(r['numbered_words'] for r in mm)} / A2 {statistics.median(r['numbered_words'] for r in a2)}")
