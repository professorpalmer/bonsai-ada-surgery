"""T4 diagnostics on a per-(row, head) dump: which probe rows and which head / block rule keep the asked needle?
Inputs: prefix.tok.i32, prefix.il<L>.rowheads.f32 ([R*H][N], row-major i = r*H + h), the server for /tokenize and
/detokenize. Prints the probe rows' text, then per rule: target kept, needles kept (of 24)."""
import argparse, json, urllib.request
import numpy as np


def call(base, key, path, body):
    req = urllib.request.Request(base + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    return json.loads(urllib.request.urlopen(req, timeout=60).read())


def find_first(hay, needle):
    idx = np.nonzero(hay == needle[0])[0]
    for i in idx:
        if i + len(needle) <= len(hay) and np.array_equal(hay[i:i + len(needle)], needle):
            return int(i)
    return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--layer", type=int, default=7)
    ap.add_argument("--rows", type=int, default=32)
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--keep", type=int, default=16384)
    ap.add_argument("--sinks", type=int, default=256)
    ap.add_argument("--window", type=int, default=2048)
    ap.add_argument("--block", type=int, default=32)
    ap.add_argument("--target", type=int, default=2)
    ap.add_argument("--n", type=int, default=24)
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    toks = np.fromfile(a.prefix + ".tok.i32", dtype=np.int32); N = len(toks)
    raw = np.memmap(a.prefix + f".il{a.layer}.rowheads.f32", dtype=np.float32, mode="r")
    RH = raw.size // N; R = a.rows; H = RH // R
    W = raw.reshape(R, H, N)
    print(f"N {N}, rows {R}, heads {H}")
    rowtxt = [call(a.base, key, "/detokenize", {"tokens": [int(t)]})["content"] for t in toks[N - R:]]
    print("probe rows:", " | ".join(f"{i}:{s!r}" for i, s in enumerate(rowtxt)))
    needles = []
    for v in range(1, a.n + 1):
        for pre in (" ", ""):
            t = np.array(call(a.base, key, "/tokenize", {"content": f"{pre}The access code for vault {v} is"})["tokens"], np.int32)
            p = find_first(toks, t)
            if p >= 0:
                needles.append((p, len(t) + 3)); break
    s_end = min(a.sinks, N); w_beg = max(s_end, N - a.window)
    starts = np.arange(s_end, w_beg, a.block)
    ends = np.minimum(starts + a.block, w_beg)

    def keep_eval(tok_score, how):
        cs = np.concatenate([[0.0], np.cumsum(tok_score[s_end:w_beg], dtype=np.float64)])
        if how == "sum":
            bs = cs[ends - s_end] - cs[starts - s_end]
        else:
            bs = np.maximum.reduceat(tok_score[s_end:w_beg], starts - s_end)
        order = np.lexsort((starts, -bs))
        n_blocks = int(np.ceil(a.keep / a.block))
        kept = np.zeros(N, bool); kept[:s_end] = True; kept[w_beg:] = True
        for k in order[:n_blocks]:
            kept[starts[k]:ends[k]] = True
        hit = [bool(kept[p:p + L].all()) for p, L in needles]
        return hit[a.target - 1], sum(hit)

    def report(name, tok_score):
        out = []
        for how in ("sum", "max"):
            t, n = keep_eval(tok_score, how)
            out.append(f"{how}: target {'Y' if t else '-'} {n:2d}/{len(needles)}")
        print(f"{name:48s} " + "   ".join(out))

    mid = slice(s_end, w_beg)
    def rows_score(rows, rule):
        sub = np.asarray(W[rows], dtype=np.float32)          # [r, H, N]
        if rule == "sum":
            return sub.sum((0, 1))
        m = sub[:, :, mid].sum(2, keepdims=True); m[m <= 0] = 1
        nrm = sub / m                                        # each (row, head) middle mass = 1
        return nrm.sum((0, 1)) if rule == "norm" else nrm.max((0, 1))
    all_rows = list(range(R))
    q_rows = [i for i, s in enumerate(rowtxt) if not any(x in s for x in ("<|im", "<think", "</think", "assistant"))]
    print("question-side rows:", q_rows)
    for rule in ("sum", "norm", "max"):
        report(f"all rows, heads {rule}", rows_score(all_rows, rule))
        report(f"question rows, heads {rule}", rows_score(q_rows, rule))
    # single rows (normalized heads, max)
    best = []
    for r in range(R):
        sc = rows_score([r], "norm")
        t, n = keep_eval(sc, "max")
        best.append((n, t, r))
        print(f"  row {r:2d} {rowtxt[r]!r:22s} norm+blockmax: target {'Y' if t else '-'} {n:2d}/{len(needles)}")
    print("best single rows:", sorted(best, reverse=True)[:5])


if __name__ == "__main__":
    main()
