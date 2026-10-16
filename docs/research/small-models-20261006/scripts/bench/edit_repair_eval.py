"""Offline score of layer/edit_repair.py on the exact-copy probe's recorded edit calls.

For each recorded call: the repair sees only what the model saw (the read tool result), then the call is judged
again with the probe's own rules. No GPU, no new samples: the same calls, with and without the repair.
  python bench/edit_repair_eval.py results/4B/exact_copy [more dirs...]
"""
import collections, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "layer"))
import exact_copy_probe as probe  # noqa: E402
import edit_repair  # noqa: E402

ITEMS = {it["id"]: it for it in probe.items()}
REJECT = ("content_mismatch", "whitespace_mismatch", "exact_not_unique")


def main(dirs):
    for d in dirs:
        rows = [json.loads(l) for l in open(os.path.join(d, "results.jsonl"), encoding="utf-8")]
        rows = [r for r in rows if "old" in r]
        before, after, changed, broke = collections.Counter(), collections.Counter(), 0, 0
        loose_b = loose_a = 0
        for r in rows:
            it = ITEMS[r["id"].split("#")[0]]
            src = f"(lines {it['a']}-{it['b']} of {it['path']})\n" + it["window"]
            old, new, info = edit_repair.repair_pair(r["old"], r["new"], [src])
            j = probe.judge(it, old, new)
            before[r["verdict"]] += 1
            after[j["verdict"]] += 1
            changed += info["repaired"]
            loose_b += bool(r.get("applied_loose"))
            loose_a += bool(j.get("applied_loose"))
            if r["verdict"] == "exact_unique" and j["verdict"] != "exact_unique":
                broke += 1
        n = len(rows)
        rb = sum(before[k] for k in REJECT)
        ra = sum(after[k] for k in REJECT)
        print(f"{d}: edit calls {n}; rejected {rb} ({100 * rb / max(1, n):.0f}%) -> {ra} ({100 * ra / max(1, n):.0f}%); "
              f"repaired {changed}; broke {broke}; comment in place {loose_b} -> {loose_a}")
        print(f"   before {dict(before)}")
        print(f"   after  {dict(after)}")


if __name__ == "__main__":
    main(sys.argv[1:])
