"""Summarize decode_trace.exe output: per step GPU busy time, idle gaps, kernel count; time by kernel name.
python summarize.py trace.csv [weight_GB]
"""
import csv
import re
import sys
from collections import defaultdict

rows = list(csv.DictReader(open(sys.argv[1])))
gb = float(sys.argv[2]) if len(sys.argv) > 2 else 0
steps = defaultdict(list)
for r in rows:
    steps[int(r["step"])].append((int(r["start_ns"]), int(r["end_ns"]), r["name"]))
ids = sorted(steps)[1:-1]  # drop the edges
busy_t, span_t, gaps_small, n_k = 0, 0, 0, 0
by_name = defaultdict(lambda: [0, 0])
for s in ids:
    ks = sorted(steps[s])
    span = ks[-1][1] - ks[0][0]
    busy, cur_s, cur_e = 0, ks[0][0], ks[0][1]
    for a, b, nm in ks:
        if a > cur_e:
            busy += cur_e - cur_s
            cur_s, cur_e = a, b
        else:
            cur_e = max(cur_e, b)
        short = re.sub(r"<.*", "", nm)[:70]
        by_name[short][0] += b - a
        by_name[short][1] += 1
    busy += cur_e - cur_s
    busy_t += busy; span_t += span; n_k += len(ks)
n = len(ids)
print(f"steps {n}: kernels {n_k / n:.0f} per step; GPU span {span_t / n / 1e6:.3f} ms, busy {busy_t / n / 1e6:.3f} ms, "
      f"idle inside the step {(span_t - busy_t) / n / 1e6:.3f} ms")
if gb:
    print(f"weights {gb:.3f} GB: {gb / (busy_t / n / 1e9):.0f} GB/s over busy time")
tot = sum(v[0] for v in by_name.values())
for nm, (t, c) in sorted(by_name.items(), key=lambda x: -x[1][0])[:30]:
    print(f"  {t / n / 1e3:8.1f} us/step {100 * t / tot:5.1f}%  x{c / n:5.0f}  {t / c / 1e3:7.2f} us each  {nm}")
