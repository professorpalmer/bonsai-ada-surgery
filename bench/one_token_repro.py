"""Repro for the 1-token answers seen on the 8 GB card (PR #9, 2026-10-08): fresh prompts longer than the f16 prefill
cap (GGML_CUDA_FA_PREFILL_F16=32768 in the 8 GB preset) sometimes get a 1-token answer. Each request is a fresh
prompt (its own filler, so no cache reuse) of about N tokens plus one question; greedy, 64 tokens. Prints the
completion tokens, the finish reason and the start of the answer for each.
    python bench/one_token_repro.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag f16cap --depths 20000,30000,33000,40000,60000
"""
import argparse, json, os, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from quick_tps import n_tokens, _headers  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--base", required=True)
ap.add_argument("--key-file", required=True)
ap.add_argument("--depths", default="20000,30000,33000,40000,60000")
ap.add_argument("--tag", default="")
ap.add_argument("--out", default="receipts/one_token_repro.jsonl")
a = ap.parse_args()
key = open(a.key_file).read().strip()

WORDS = ["river", "lamp", "copper", "orchard", "signal", "harbor", "violet", "granite", "lantern", "meadow", "cipher", "falcon"]


def filler(target, seed):
    def sent(i):
        return f"Note {seed}-{i}: the {WORDS[(i + seed) % 12]} report lists {WORDS[(i * 7 + seed) % 12]} counts of {(i * 37 + seed) % 997} for site {i % 41}."
    n = max(1, target // 22)
    text = " ".join(sent(i) for i in range(n))
    got = n_tokens(a.base, key, text)
    n = max(1, int(n * target / max(1, got)))
    return " ".join(sent(i) for i in range(n))


for k, d in enumerate(int(x) for x in a.depths.split(",")):
    seed = int(time.time()) % 100000 + k * 7919
    text = filler(d, seed) + "\n\nQuestion: in two sentences, what kind of records are listed above, and which site number appears first?"
    body = {"messages": [{"role": "user", "content": text}], "max_tokens": 64, "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=_headers(key))
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(req, timeout=3600).read())
    t = r.get("timings") or {}
    ch = r["choices"][0]
    content = ch["message"].get("content") or ""
    rec = {"tag": a.tag, "depth": d, "prompt_n": t.get("prompt_n"), "completion": t.get("predicted_n") or r.get("usage", {}).get("completion_tokens"),
           "finish": ch.get("finish_reason"), "head": content[:70].replace("\n", " "), "seconds": round(time.time() - t0, 1)}
    print(json.dumps(rec), flush=True)
    with open(a.out, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")
