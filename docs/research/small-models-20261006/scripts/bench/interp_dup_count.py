"""How many of the layer's run_python rounds repeat an earlier round of the same request? Offline, from suite traces
(results/<model>/suite/traces/*-layer.json, interpreter_trace). Same code = identical code text; same output = the
same stdout head and exit code as an earlier round (for computation tasks the printed result is the behaviour).
    python bench/interp_dup_count.py 9B 9B-base 4B 4B-base 2B 2B-base
"""
import glob, json, os, sys, collections

for m in sys.argv[1:]:
    fam = collections.defaultdict(lambda: collections.Counter())
    for p in glob.glob(f"results/{m}/suite/traces/*-layer.json"):
        family = os.path.basename(p).split("-")[0]
        try:
            t = json.load(open(p, encoding="utf-8"))
        except Exception:
            continue
        tr = t.get("interpreter_trace") or [] if isinstance(t, dict) else []
        c = fam[family]
        c["requests"] += 1
        c["rounds"] += len(tr)
        seen_code, seen_out = set(), set()
        for r in tr:
            code = r.get("code") or ""
            out = (r.get("exit_code"), r.get("stdout_head") or "", r.get("stderr_head") or "")
            if code in seen_code:
                c["same_code"] += 1
            elif out in seen_out and (out[1] or out[2]):
                c["same_output"] += 1
            seen_code.add(code); seen_out.add(out)
        if len(tr) >= 12:
            c["hit_round_cap"] += 1
    for f, c in sorted(fam.items()):
        r = c["rounds"] or 1
        print(f"{m:8s} {f:12s} requests {c['requests']:3d} rounds {c['rounds']:4d} (cap hit {c['hit_round_cap']:2d})  "
              f"same code {c['same_code']:3d} ({100*c['same_code']/r:4.1f}%)  same output, new code {c['same_output']:3d} ({100*c['same_output']/r:4.1f}%)")
