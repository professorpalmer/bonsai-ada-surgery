"""Exact code retrieval deep in a long prompt: ~DEPTH tokens of Python source (artifacts/eval/pycode.raw, files in order),
then one request per target function: "output the exact source of function F from file X". Targets are short top-level
functions (4-20 lines) at evenly spaced positions. Exact match after stripping trailing spaces per line. Same prefix
for every request (the server reuses the cached prompt). Measures what sparse reading of the host tail
(GGML_CUDA_FA_SPARSE) costs on code, against the dense cache. Light on RAM (no logits kept).

python bench/code_needle.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 160000 --n 10 --tag dense
"""
import argparse, ast, json, os, re, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from quick_tps import n_tokens  # noqa: E402

CORPUS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "artifacts", "eval", "pycode.raw")


def post(base, key, body):
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    return json.loads(urllib.request.urlopen(req, timeout=3600).read()), time.time() - t0


def norm(code):
    return "\n".join(l.rstrip() for l in code.strip("\n").splitlines())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--depth", type=int, default=160000)
    ap.add_argument("--n", type=int, default=10)
    ap.add_argument("--tag", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    text = open(CORPUS, encoding="utf-8").read()
    parts = re.split(r"(?m)^# ===== (.+?) =====\n", text)[1:]
    files = list(zip(parts[0::2], parts[1::2]))
    # grow the context file by file to about DEPTH tokens (estimate 3.6 chars per token, then one correction)
    def build(chars):
        out, n = [], 0
        for name, src in files:
            if n >= chars:
                break
            out.append((name, src))
            n += len(src)
        return out
    chosen = build(int(a.depth * 3.6))
    ctx = "".join(f"# ===== {n} =====\n{s}" for n, s in chosen)
    got = n_tokens(a.base, key, ctx)
    chosen = build(int(a.depth * 3.6 * a.depth / max(1, got)))
    ctx = "".join(f"# ===== {n} =====\n{s}" for n, s in chosen)
    # candidate targets: short top-level functions with a unique name across the context
    cands, seen = [], {}
    offset = 0
    for name, src in chosen:
        block = f"# ===== {name} =====\n{src}"
        try:
            tree = ast.parse(src)
        except SyntaxError:
            tree = None
        if tree:
            lines = src.splitlines()
            for node in tree.body:
                if isinstance(node, ast.FunctionDef):
                    seen[node.name] = seen.get(node.name, 0) + 1
                    if 4 <= node.end_lineno - node.lineno + 1 <= 20 and not node.decorator_list:
                        code = "\n".join(lines[node.lineno - 1:node.end_lineno])
                        cands.append({"file": name, "fn": node.name, "code": code,
                                      "pos": offset + src.find(code) + len(f"# ===== {name} =====\n")})
        offset += len(block)
    cands = [c for c in cands if seen[c["fn"]] == 1]
    targets = [min(cands, key=lambda c: abs(c["pos"] - len(ctx) * (k + 0.5) / a.n)) for k in range(a.n)]
    ok = 0
    for t in targets:
        q = (f"From the file `{t['file']}` above, output the exact source code of the function `{t['fn']}`, "
             "unchanged, in one python code block. Output nothing else.")
        body = {"messages": [{"role": "user", "content": "Python source files:\n\n" + ctx + "\n\n" + q}],
                "max_tokens": 800, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
        r, dt = post(a.base, key, body)
        ans = r["choices"][0]["message"]["content"] or ""
        m = re.search(r"```(?:python)?\n(.*?)```", ans, re.S)
        hit = norm(m.group(1) if m else ans) == norm(t["code"])
        ok += hit
        rec = {"tag": a.tag, "depth": a.depth, "file": t["file"], "fn": t["fn"], "position_frac": round(t["pos"] / len(ctx), 3),
               "lines": t["code"].count("\n") + 1, "ok": hit, "evaluated": r.get("timings", {}).get("prompt_n"), "wall_s": round(dt, 1)}
        print(json.dumps(rec), flush=True)
        if a.out:
            with open(a.out, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec) + "\n")
    print(json.dumps({"tag": a.tag, "depth": a.depth, "correct": ok, "of": len(targets)}), flush=True)


if __name__ == "__main__":
    main()
