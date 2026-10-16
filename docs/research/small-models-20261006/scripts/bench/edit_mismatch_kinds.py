"""Classify the exact-copy probe's rejected edit calls that the indentation repair does not fix.
  python bench/edit_mismatch_kinds.py results/4B/exact_copy [more dirs...]"""
import collections, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "layer"))
import exact_copy_probe as probe  # noqa: E402
import edit_repair  # noqa: E402

ITEMS = {it["id"]: it for it in probe.items()}
NL, BSN = "\n", "\\" + "n"


def kind(x, it):
    old, w = x["old"], it["window"]
    _, _, info = edit_repair.repair_pair(old, x["new"], [w])
    if info["repaired"]:
        return "indentation (repaired)"
    if NL not in old and BSN in old:
        return "escaped line breaks"
    ol = [l.strip() for l in old.split(NL) if l.strip()]
    if not ol:
        return "empty old text"
    wl = [l.strip() for l in w.split(NL)]
    if len(ol) == 1:
        if sum(1 for l in wl if l == ol[0]) > 1:
            return "one line, several matches"
        if any(ol[0] in l for l in wl):
            return "part of one line"
    for i, l in enumerate(wl):
        if l == ol[0]:
            j, k = i, 0
            while j < len(wl) and k < len(ol) and j - i < len(ol) + 6:
                if wl[j] == ol[k]:
                    k += 1
                j += 1
            if k == len(ol):
                return "lines left out"
    return "other (changed or invented text)"


for d in sys.argv[1:]:
    rows = [json.loads(l) for l in open(os.path.join(d, "results.jsonl"), encoding="utf-8")]
    rows = [x for x in rows if "old" in x and x["verdict"] == "content_mismatch"]
    c = collections.Counter(kind(x, ITEMS[x["id"].split("#")[0]]) for x in rows)
    print(f"{d}: {len(rows)} content mismatches: {dict(c)}")
