"""Byte-for-byte tensor comparison of two GGUFs, plus the metadata (KV) differences.

    python bench/gguf_tensor_identity.py BASE.gguf GRAFTED.gguf [--ignore-prefix blk.64.]

Prints: tensors only in one file, tensors whose bytes differ, metadata keys added/removed/changed. Exit 0 when every
shared tensor outside the ignored prefix is byte-identical. Uses the fork's gguf-py (knows PrismML's tensor types).
"""
import argparse, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "vendor", "prism-llama", "gguf-py"))
from gguf import GGUFReader  # noqa: E402

def kv_map(r):
    out = {}
    for k, f in r.fields.items():
        try:
            if len(f.types) == 1 and f.types[0].name == "STRING":
                v = bytes(f.parts[f.data[0]]).decode("utf-8", "replace")
            elif f.types and f.types[0].name == "ARRAY":
                v = f"<array len={len(f.data)}>"
            else:
                v = f.parts[f.data[0]].tolist() if f.data else None
        except Exception as e:  # pragma: no cover
            v = f"<unreadable {e}>"
        out[k] = v
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base"); ap.add_argument("other"); ap.add_argument("--ignore-prefix", default="blk.64.")
    a = ap.parse_args()
    rb, ro = GGUFReader(a.base), GGUFReader(a.other)
    tb = {t.name: t for t in rb.tensors}; to = {t.name: t for t in ro.tensors}
    only_b = sorted(set(tb) - set(to)); only_o = sorted(set(to) - set(tb))
    same = diff = 0; differing = []
    for name in sorted(set(tb) & set(to)):
        x, y = tb[name], to[name]
        if x.tensor_type != y.tensor_type or tuple(x.shape) != tuple(y.shape) or x.data.nbytes != y.data.nbytes \
                or x.data.tobytes() != y.data.tobytes():
            diff += 1; differing.append(name)
        else:
            same += 1
    print(f"tensors: {len(tb)} in base, {len(to)} in other; shared {same + diff}: {same} byte-identical, {diff} differ")
    print(f"only in base: {only_b[:10]}{' ...' if len(only_b) > 10 else ''}")
    extra = [n for n in only_o if not n.startswith(a.ignore_prefix)]
    print(f"only in other: {len(only_o)} (of which {len(only_o) - len(extra)} under {a.ignore_prefix!r}); outside the prefix: {extra[:10]}")
    if differing: print("differing tensors:", differing[:20])
    kb, ko = kv_map(rb), kv_map(ro)
    added = sorted(set(ko) - set(kb)); removed = sorted(set(kb) - set(ko))
    changed = sorted(k for k in set(kb) & set(ko) if kb[k] != ko[k])
    print(f"metadata: {len(kb)} keys in base, {len(ko)} in other; added {added}; removed {removed}; changed {changed}")
    for k in changed[:10]:
        print(f"  {k}: base={str(kb[k])[:120]!r} other={str(ko[k])[:120]!r}")
    diff_outside = [n for n in differing if not n.startswith(a.ignore_prefix)]   # changes inside the prefix are expected
    ok = (not diff_outside and not only_b and not extra)
    print("RESULT:", "every shared tensor outside the prefix is byte-identical" if ok else "DIFFERENCES FOUND")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
