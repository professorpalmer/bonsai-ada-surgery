"""Facts deep in a long prompt: can the model still retrieve them? One ~DEPTH-token filler with N unique facts
("The access code for vault 7 is 4182.") at evenly spaced positions, then one question per fact, each a separate
request with the same prefix (the server reuses the cached prompt). Exact match on the 4-digit code. Used to measure
what sparse reading of the host tail (GGML_CUDA_FA_SPARSE) costs in retrieval, against the dense cache.

python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 160000 --n 12 --tag dense
"""
import argparse, json, os, random, re, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from quick_tps import n_tokens  # noqa: E402

SUBJ = ["the archive", "a survey", "the committee", "one report", "the ledger", "a memo", "the register", "field notes"]
VERB = ["records", "lists", "mentions", "summarizes", "notes", "confirms", "tracks", "describes"]
OBJ = ["shipments", "rainfall totals", "meeting dates", "inventory counts", "repair logs", "visitor numbers",
       "budget lines", "soil samples", "route changes", "maintenance windows"]


def sentence(i):
    return f"{SUBJ[i % 8].capitalize()} {VERB[(i // 8) % 8]} {OBJ[(i // 64) % 10]} for entry {i}."


def post(base, key, body):
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    return json.loads(urllib.request.urlopen(req, timeout=3600).read()), time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--depth", type=int, default=160000)
    ap.add_argument("--n", type=int, default=12)
    ap.add_argument("--tag", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    rng = random.Random(7)
    codes = {v: f"{rng.randrange(1000, 10000)}" for v in range(1, a.n + 1)}
    n_sent = max(1, a.depth // 12)
    probe = " ".join(sentence(i) for i in range(n_sent))
    n_sent = max(1, int(n_sent * a.depth / max(1, n_tokens(a.base, key, probe))))
    slots = {int(n_sent * (k + 0.5) / a.n): v for k, v in enumerate(range(1, a.n + 1))}
    parts = []
    for i in range(n_sent):
        if i in slots:
            v = slots[i]
            parts.append(f"The access code for vault {v} is {codes[v]}.")
        parts.append(sentence(i))
    doc = "Facility notes:\n" + " ".join(parts) + "\n\n"
    ok = 0
    for v in range(1, a.n + 1):
        body = {"messages": [{"role": "user", "content": doc + f"What is the access code for vault {v}? Answer with the 4 digits only."}],
                "max_tokens": 16, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
        r, dt = post(a.base, key, body)
        ans = r["choices"][0]["message"]["content"]
        got = re.findall(r"\d{4}", ans)
        hit = bool(got) and got[0] == codes[v]
        ok += hit
        rec = {"tag": a.tag, "depth": a.depth, "vault": v, "position_frac": round((v - 0.5) / a.n, 3), "want": codes[v],
               "answer": ans.strip()[:40], "ok": hit, "evaluated": r.get("timings", {}).get("prompt_n"), "wall_s": round(dt, 1)}
        print(json.dumps(rec), flush=True)
        if a.out:
            with open(a.out, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec) + "\n")
    print(json.dumps({"tag": a.tag, "depth": a.depth, "correct": ok, "of": a.n}), flush=True)


if __name__ == "__main__":
    main()
