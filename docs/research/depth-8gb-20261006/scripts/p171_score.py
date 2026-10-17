"""P171 scorer: a small model (Qwen2.5-1.5B-Instruct q4_k_m, already in the local HF cache) rates every chunk of a P170
document against each question: P(Yes) / (P(Yes) + P(No)) for "Does the passage contain the answer to the question?".
The chunks are the same as p170_drive.py's (chunks_of, 400 chars). It runs against a plain llama-server on :8090 (many
slots; the question comes first, so each slot reuses the cached instruction + question prefix). Output:
p170/scores_<set>.json = {"chunks": N, "items": [[score per chunk], ...], "seconds": [per item]}.

python p171_score.py --set prose --threads 16
"""
import argparse, json, math, re, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

ap = argparse.ArgumentParser()
ap.add_argument("--set", choices=["prose", "code"], required=True)
ap.add_argument("--threads", type=int, default=16)
ap.add_argument("--base", default="http://127.0.0.1:8090")
ap.add_argument("--only", type=int, default=0)
a = ap.parse_args()

S = json.load(open(rf"C:/bonsai/8gb/p170/{a.set}.json", encoding="utf-8"))
doc, items = S["doc"], S["items"][: a.only or None]


def chunks_of(text, cap):  # the same split as p170_drive.py
    blocks = re.split(r"(\n\s*\n)", text)
    out, cur = [], ""
    for b in blocks:
        if len(cur) + len(b) <= cap:
            cur += b
            continue
        if cur:
            out.append(cur)
        cur = ""
        while len(b) > cap:
            cut = b.rfind("\n", 0, cap)
            cut = cut if cut > cap // 4 else cap
            out.append(b[:cut])
            b = b[cut:]
        cur = b
    if cur:
        out.append(cur)
    return out


CH = chunks_of(doc, 400)


def post(body):
    req = urllib.request.Request(a.base + "/completion", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=600).read())


def yes_no(r):
    p = {}
    cps = r.get("completion_probabilities") or []
    if cps:
        c = cps[0]
        for t in c.get("top_logprobs") or []:
            p[t["token"].strip().lower()] = p.get(t["token"].strip().lower(), 0) + math.exp(t["logprob"])
        for t in c.get("probs") or []:
            k = (t.get("tok_str") or t.get("token") or "").strip().lower()
            p[k] = p.get(k, 0) + t.get("prob", 0)
    y, n = p.get("yes", 0.0), p.get("no", 0.0)
    return y / (y + n) if y + n > 0 else 0.0


def prompt(q, c):
    q = q.replace("In the code above, ", "").replace(" Answer with the number only.", "")
    return ("<|im_start|>system\nYou check whether a passage answers a question.<|im_end|>\n<|im_start|>user\n"
            f"Question: {q}\n\nPassage:\n{c}\n\nDoes the passage contain the answer to the question? Reply Yes or No."
            "<|im_end|>\n<|im_start|>assistant\n")


out = {"chunks": len(CH), "items": [], "seconds": []}
with ThreadPoolExecutor(a.threads) as ex:
    for n, it in enumerate(items, 1):
        t0 = time.time()
        sc = list(ex.map(lambda c: yes_no(post({"prompt": prompt(it["q"], c), "n_predict": 1, "n_probs": 20,
                                                 "temperature": 0, "cache_prompt": True})), CH))
        dt = time.time() - t0
        fk = next((k for k, c in enumerate(CH) if it["fact"] in c), None)
        rank = sorted(range(len(CH)), key=lambda k: -sc[k]).index(fk) + 1 if fk is not None else None
        out["items"].append(sc)
        out["seconds"].append(round(dt, 1))
        print(json.dumps({"set": a.set, "item": n, "s": round(dt, 1), "fact_chunk": fk, "fact_score": round(sc[fk], 3)
                          if fk is not None else None, "fact_rank": rank, "n_over_0.5": sum(s > 0.5 for s in sc)}), flush=True)
json.dump(out, open(rf"C:/bonsai/8gb/p170/scores_{a.set}.json", "w", encoding="utf-8"))
