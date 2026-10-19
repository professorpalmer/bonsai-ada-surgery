"""Count tokens of the shortlist corpus, write llama-mtp-vocab-v1 maps, report held-out coverage (gate S0).
python make_map.py CORPUS_DIR OUT_DIR [traces.jsonl]
Weights: model output (answers, thinking traces) 3, every other category 1; the score of a token is the sum over
categories of weight x (its share of that category's tokens). Always in the map: control / user-defined / byte tokens."""
import collections, json, os, subprocess, sys

CORPUS, OUT = sys.argv[1], sys.argv[2]
TRACES = sys.argv[3] if len(sys.argv) > 3 else None
MODEL = r"<models>/Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
TOK = r"<checkout>/bin/llama-tokenize.exe"
CU = r"<home>/AppData/Local/Programs/Python/Python312/Lib/site-packages/nvidia/cu13"
ENV = dict(os.environ, CUDA_VISIBLE_DEVICES="-1", PATH=CU + "/bin;" + CU + "/bin/x86_64;" + os.environ["PATH"])
os.makedirs(OUT, exist_ok=True)


def tokenize_file(path):
    r = subprocess.run([TOK, "-m", MODEL, "-f", path, "--ids", "--log-disable"], capture_output=True, text=True,
                       env=ENV, timeout=3600)
    line = [l for l in r.stdout.splitlines() if l.startswith("[")]
    if r.returncode != 0 or not line:
        raise SystemExit(f"tokenize failed on {path}: rc {r.returncode} {r.stderr[-300:]}")
    return json.loads(line[-1])


def tokenize_text(name, text):
    p = os.path.join(OUT, name)
    open(p, "w", encoding="utf-8").write(text)
    return tokenize_file(p)


# vocabulary facts from the GGUF header
sys.path.insert(0, r"<checkout>/gguf-py")
import gguf  # noqa: E402
rd = gguf.GGUFReader(MODEL)
f_types = rd.fields["tokenizer.ggml.token_type"]
types = [int(f_types.parts[i][0]) for i in f_types.data]
f_tok = rd.fields["tokenizer.ggml.tokens"]
toks = [bytes(f_tok.parts[i]).decode("utf-8", "replace") for i in f_tok.data]
n_vocab = len(toks)
always = {i for i, t in enumerate(types) if t in (3, 4, 6)}   # CONTROL, USER_DEFINED, BYTE
always |= {i for i, s in enumerate(toks) if len(s) == 1}       # single characters
print(f"vocab {n_vocab}, always-in {len(always)}")

build, held = {}, {}
for fn in sorted(os.listdir(CORPUS)):
    ids = tokenize_file(os.path.join(CORPUS, fn))
    (held if fn.startswith("heldout_") else build)[fn] = ids
    print(f"{fn}: {len(ids):,} tokens")

if TRACES:
    recs = [json.loads(l) for l in open(TRACES, encoding="utf-8") if l.strip()]
    recs = [r for r in recs if not r.get("error")]
    def text(r):
        return r.get("reasoning", "") + "\n" + r.get("content", "") + "\n" + json.dumps(r.get("tool_calls") or [])
    tr_build = "\n\n".join(text(r) for r in recs if r["i"] % 5 != 0)
    tr_held = "\n\n".join(text(r) for r in recs if r["i"] % 5 == 0)
    build["traces.txt"] = tokenize_text("_traces_build.txt", tr_build)
    held["heldout_traces.txt"] = tokenize_text("_traces_held.txt", tr_held)
    print(f"traces: build {len(build['traces.txt']):,}, held out {len(held['heldout_traces.txt']):,} tokens")

score = collections.Counter()
for fn, ids in build.items():
    w = 3.0 if fn in ("model_answers.txt", "traces.txt") else 1.0
    c = collections.Counter(ids)
    tot = sum(c.values())
    for t, n in c.items():
        score[t] += w * n / tot
ranked = [t for t, _ in score.most_common()]
print(f"distinct tokens seen in the build set: {len(ranked):,}")

# S0b fill: the lowest-id ASCII tokens (byte-level BPE: id order = merge rank), after the corpus ranking
def _bytes_to_unicode():
    bs = list(range(ord("!"), ord("~") + 1)) + list(range(ord("¡"), ord("¬") + 1)) + list(range(ord("®"), ord("ÿ") + 1))
    cs = bs[:]
    n = 0
    for b in range(256):
        if b not in bs:
            bs.append(b); cs.append(256 + n); n += 1
    return {chr(c): b for b, c in zip(bs, cs)}
_dec = _bytes_to_unicode()
def _ascii(s):
    try:
        return all(_dec[ch] < 128 for ch in s)
    except KeyError:
        return False
FILL = os.environ.get("SHORTLIST_FILL") == "1"
fill_order = [i for i in range(n_vocab) if types[i] == 1 and _ascii(toks[i])] if FILL else []
print(f"fill: {'on, ' + str(len(fill_order)) + ' ASCII tokens by id' if FILL else 'off'}")

report = {}
for size in (16384, 24576, 32768):
    sel = list(always)
    have = set(sel)
    for t in ranked:
        if len(sel) >= size:
            break
        if t not in have:
            sel.append(t); have.add(t)
    for t in fill_order:
        if len(sel) >= size:
            break
        if t not in have:
            sel.append(t); have.add(t)
    sel = sorted(set(sel))[:size]
    s = set(sel)
    cov = {fn: round(100.0 * sum(1 for t in ids if t in s) / max(1, len(ids)), 3) for fn, ids in held.items()}
    report[size] = cov
    path = os.path.join(OUT, f"bonsai-mtp-vocab-{size // 1024}k.txt")
    with open(path, "w", encoding="ascii") as f:
        f.write(f"llama-mtp-vocab-v1 {n_vocab} {len(sel)}\n")
        f.write("\n".join(str(t) for t in sel) + "\n")
    print(f"{size}: {len(sel)} ids -> {os.path.basename(path)}; held-out coverage {cov}")
json.dump(report, open(os.path.join(OUT, "coverage.json"), "w"), indent=1)
