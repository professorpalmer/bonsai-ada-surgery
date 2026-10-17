"""T4 diagnostics: which aggregation of the probe-layer attention keeps the needles?
Input: the LLAMA_FAST_READ_DUMP files of one request (prefix.tok.i32, prefix.il<L>.heads.f32 [H][N]) and the server URL
for /tokenize (to find the needle sentences in the token array). Prints, per aggregation, how many of the needles fall in
kept blocks (sinks + window + best blocks up to KEEP tokens, as the server selects)."""
import argparse, json, sys, urllib.request
import numpy as np


def tokenize(base, key, text):
    req = urllib.request.Request(base + "/tokenize", data=json.dumps({"content": text}).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    return json.loads(urllib.request.urlopen(req, timeout=60).read())["tokens"]


def find_all(hay, needle):
    n = len(needle); out = []
    first = needle[0]
    idx = np.nonzero(hay == first)[0]
    for i in idx:
        if i + n <= len(hay) and np.array_equal(hay[i:i + n], needle):
            out.append(int(i))
    return out


def select(score, n, keep, sinks, window, block):
    kept = np.zeros(n, bool)
    s_end = min(sinks, n); w_beg = max(s_end, n - window)
    kept[:s_end] = True; kept[w_beg:] = True
    starts = np.arange(s_end, w_beg, block)
    bs = np.array([score[s:min(s + block, w_beg)].sum() for s in starts]) if score.ndim == 1 else None
    return kept, starts, s_end, w_beg


TARGET = [0]


def run(name, block_scores, starts, kept0, w_beg, keep, block, needles):
    order = np.lexsort((starts, -block_scores))
    kept = kept0.copy(); n_mid = 0
    for k in order:
        if n_mid >= keep:
            break
        s = starts[k]; e = min(s + block, w_beg)
        kept[s:e] = True; n_mid += e - s
    hit = [all(kept[p:p + L]) for p, L in needles]
    tk = ("target kept " + str(hit[TARGET[0] - 1])) if TARGET[0] and TARGET[0] <= len(hit) else ""
    print(f"{name:42s} {tk:18s} needles kept {sum(hit):2d}/{len(hit)}  missing at frac "
          f"{[round(needles[i][0] / len(kept), 3) for i, h in enumerate(hit) if not h][:12]}")
    return hit


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--layer", type=int, default=7)
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--keep", type=int, default=16384)
    ap.add_argument("--sinks", type=int, default=256)
    ap.add_argument("--window", type=int, default=2048)
    ap.add_argument("--block", type=int, default=32)
    ap.add_argument("--n", type=int, default=24)
    ap.add_argument("--target", type=int, default=0, help="the vault the question asks for")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    TARGET[0] = a.target
    toks = np.fromfile(a.prefix + ".tok.i32", dtype=np.int32)
    N = len(toks)
    heads = np.fromfile(a.prefix + f".il{a.layer}.heads.f32", dtype=np.float32)
    H = heads.size // N
    heads = heads.reshape(H, N)
    print(f"N {N}, heads {H}, per-head mass {heads.sum(1).round(1).tolist()[:8]} ...")
    # the needle sentences: "The access code for vault V is"
    needles = []
    for v in range(1, a.n + 1):
        t = tokenize(a.base, key, f" The access code for vault {v} is")
        pos = find_all(toks, np.array(t, np.int32))
        if not pos:
            t = tokenize(a.base, key, f"The access code for vault {v} is")
            pos = find_all(toks, np.array(t, np.int32))
        if pos:
            needles.append((pos[0], len(t) + 3))
        else:
            print(f"vault {v}: sentence not found in the tokens")
    print(f"needles found: {len(needles)} at frac {[round(p / N, 3) for p, _ in needles][:6]} ...")
    kept0, starts, s_end, w_beg = select(heads[0], N, a.keep, a.sinks, a.window, a.block)
    def blocks_of(tok_scores, how="sum"):
        out = np.empty(len(starts), np.float64)
        for k, s in enumerate(starts):
            seg = tok_scores[s:min(s + a.block, w_beg)]
            out[k] = seg.sum() if how == "sum" else seg.max()
        return out
    # aggregations
    tot = heads.sum(0)
    run("A0 sum heads, block sum (the server)", blocks_of(tot), starts, kept0, w_beg, a.keep, a.block, needles)
    run("A1 sum heads, block max", blocks_of(tot, "max"), starts, kept0, w_beg, a.keep, a.block, needles)
    mid = slice(s_end, w_beg)
    norm = heads / np.maximum(heads[:, mid].sum(1, keepdims=True), 1e-30)   # each head's middle mass = 1
    run("A2 head-normalized (middle mass), sum", blocks_of(norm.sum(0)), starts, kept0, w_beg, a.keep, a.block, needles)
    run("A3 head-normalized, block max", blocks_of(norm.sum(0), "max"), starts, kept0, w_beg, a.keep, a.block, needles)
    run("A4 max over heads, block max", blocks_of(norm.max(0), "max"), starts, kept0, w_beg, a.keep, a.block, needles)
    # per-head ranks: blocks kept by each head's own top-k, combined by best rank
    hb = np.stack([blocks_of(norm[h]) for h in range(H)])
    ranks = np.argsort(np.argsort(-hb, axis=1), axis=1)
    run("A5 best rank over heads", -ranks.min(0).astype(np.float64), starts, kept0, w_beg, a.keep, a.block, needles)
    # which heads see the needles: needle-mass fraction per head
    nm = np.array([sum(norm[h, p:p + L].sum() for p, L in needles) for h in range(H)])
    print("needle mass per head (top 8):", sorted(enumerate(nm.round(4)), key=lambda x: -x[1])[:8])
    top = np.argsort(-nm)[:4]
    run(f"A6 top-4 needle heads {top.tolist()} (oracle)", blocks_of(norm[top].sum(0)), starts, kept0, w_beg, a.keep, a.block, needles)


if __name__ == "__main__":
    main()
