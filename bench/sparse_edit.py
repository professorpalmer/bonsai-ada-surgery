"""Deep prompt edit against the sparse fast path's cached page bounds (GGML_CUDA_FA_SPARSE_FAST). Needs a server
started with GGML_CUDA_FA_SPARSE_CHECK=1, which logs every attention op whose cached bounds differ from fresh ones.
Requests on one prefix of ~DEPTH tokens of Python files (artifacts/eval/pycode.raw):
  1 base:  the files + a question (cold prefill, fills the bounds tables during decode)
  2 edit:  the same files with the file at EDIT_FRAC of the context replaced by another one (the server keeps the
           prefix up to it and writes the rest again, deep in the host tail) + the question
  3 again: request 2 repeated (prefix fully cached; decode only)
Per request: the stale-bound lines the server logged during it (0 = the bounds follow the writes), and the ops whose
page selection on the device differs from the host one (0 = same pages).

python bench/sparse_edit.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --log logs/x.server.log
"""
import argparse, json, os, re, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from quick_tps import n_tokens  # noqa: E402

CORPUS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "artifacts", "eval", "pycode.raw")


def post(base, key, body):
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    return json.loads(urllib.request.urlopen(req, timeout=7200).read()), time.time() - t0


def check_lines(log):
    # (ops with stale cached bounds, ops whose device page selection differs from the host one)
    try:
        with open(log, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return 0, 0
    return sum("CHECK stale bounds" in l for l in lines), sum("CHECK selection differs" in l for l in lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--log", required=True, help="the server's stderr log")
    ap.add_argument("--depth", type=int, default=160000)
    ap.add_argument("--edit-frac", type=float, default=0.9)
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    text = open(CORPUS, encoding="utf-8").read()
    parts = re.split(r"(?m)^# ===== (.+?) =====\n", text)[1:]
    files = list(zip(parts[0::2], parts[1::2]))

    def take(chars):
        out, n = [], 0
        for f in files:
            if n >= chars:
                break
            out.append(f)
            n += len(f[1])
        return out

    chosen = take(int(a.depth * 3.6))
    ctx = "".join(f"# ===== {n} =====\n{s}" for n, s in chosen)
    chosen = take(int(a.depth * 3.6 * a.depth / max(1, n_tokens(a.base, key, ctx))))
    # the file at edit_frac of the context, and an unused file of similar size to put there
    total = sum(len(s) for _, s in chosen)
    acc, m = 0, 0
    for m, (_, s) in enumerate(chosen):
        acc += len(s)
        if acc >= a.edit_frac * total:
            break
    rest = files[len(chosen):]
    repl = min(rest, key=lambda f: abs(len(f[1]) - len(chosen[m][1])))
    edited = chosen[:m] + [repl] + chosen[m + 1:]
    q = "\n\nIn one sentence: what does the last file above do?"

    def ask(files_, label):
        before = check_lines(a.log)
        body = {"messages": [{"role": "user", "content": "".join(f"# ===== {n} =====\n{s}" for n, s in files_) + q}],
                "max_tokens": 48, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
        r, dt = post(a.base, key, body)
        time.sleep(1)
        rec = {"tag": a.tag, "request": label, "prompt_n": r.get("timings", {}).get("prompt_n"),
               "predicted_n": r.get("timings", {}).get("predicted_n"), "stale_ops": check_lines(a.log)[0] - before[0],
               "select_diff_ops": check_lines(a.log)[1] - before[1],
               "wall_s": round(dt, 1), "answer": (r["choices"][0]["message"]["content"] or "")[:120]}
        print(json.dumps(rec), flush=True)

    print(json.dumps({"tag": a.tag, "files": len(chosen), "edit_file": m, "edit_char_frac": round(acc / total, 3)}), flush=True)
    ask(chosen, "base")
    ask(edited, "edit")
    ask(edited, "again")


if __name__ == "__main__":
    main()
