"""Which held-out trace tokens does the 32k map miss? python misses.py MAPS_DIR"""
import collections, json, os, re, subprocess, sys

D = sys.argv[1]
MODEL = r"<models>/Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
TOK = r"<checkout>/bin/llama-tokenize.exe"
CU = r"<home>/AppData/Local/Programs/Python/Python312/Lib/site-packages/nvidia/cu13"
ENV = dict(os.environ, CUDA_VISIBLE_DEVICES="-1", PATH=CU + "/bin;" + CU + "/bin/x86_64;" + os.environ["PATH"])
sel = set(int(x) for x in open(os.path.join(D, "bonsai-mtp-vocab-32k.txt")).read().split()[3:])
r = subprocess.run([TOK, "-m", MODEL, "-f", os.path.join(D, "_traces_held.txt"), "--ids", "--log-disable"],
                   capture_output=True, text=True, env=ENV)
ids = json.loads([l for l in r.stdout.splitlines() if l.startswith("[")][-1])
r2 = subprocess.run([TOK, "-m", MODEL, "-f", os.path.join(D, "_traces_held.txt"), "--log-disable"],
                    capture_output=True, text=True, env=ENV, encoding="utf-8", errors="replace")
pieces = {}
for line in r2.stdout.splitlines():
    m = re.match(r"\s*(\d+) -> '(.*)'$", line)
    if m:
        pieces[int(m.group(1))] = m.group(2)
miss = collections.Counter(t for t in ids if t not in sel)
print(f"held-out tokens {len(ids)}, missed {sum(miss.values())} ({100 * sum(miss.values()) / len(ids):.2f} %), distinct missed {len(miss)}")
def kind(p):
    if re.fullmatch(r"[ A-Za-z]+", p): return "latin word"
    if re.fullmatch(r"[ 0-9]+", p): return "digits"
    if any(ord(c) > 127 for c in p): return "non-ascii"
    return "symbol/other"
k = collections.Counter()
for t, n in miss.items():
    k[kind(pieces.get(t, "?"))] += n
print("by kind:", dict(k))
print("top 40:", [(pieces.get(t, "?"), n) for t, n in miss.most_common(40)])
