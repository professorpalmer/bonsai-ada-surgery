"""P189 driver (the P170 driver plus top-20 log-probabilities of each answer token, for a drift score):
P170 driver: a text-match pre-filter ("lex") vs the full read ("dense") on the product server, no engine change.
dense: user = doc + blank line + question, one request per item (the server reuses the cached document prefix).
lex:   the document is split into chunks; each chunk gets a BM25 score against the question's words (lowercase words, an
       identifier also split at case changes; a stop list); keep the first chunks up to SINKS tokens, the last chunks up to
       WINDOW tokens, then the best chunks up to KEEP tokens in all; join them in document order ("[...]" marks a gap);
       user = kept text + blank line + question. A fresh prompt per item.
Grade: prose = an answer keyword is in the answer (lowercase); code = the first number in the answer equals the value.

python p170_drive.py --set prose --arm lex --keep 16384 --key-file K --out receipts/p170/x.jsonl
"""
import argparse, json, math, os, re, time, urllib.request
from collections import Counter

ap = argparse.ArgumentParser()
ap.add_argument("--set", choices=["prose", "code"], required=True)
ap.add_argument("--arm", choices=["dense", "lex", "small", "mix"], required=True)
ap.add_argument("--keep", type=int, default=16384)
ap.add_argument("--sinks", type=int, default=256)
ap.add_argument("--window", type=int, default=2048)
ap.add_argument("--chunk-chars", type=int, default=400)
ap.add_argument("--base", default="http://127.0.0.1:8080")
ap.add_argument("--key-file", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--only", type=int, default=0, help="run the first N items only (0 = all)")
ap.add_argument("--dry", action="store_true", help="lex: selection only, no chat request")
a = ap.parse_args()
key = open(a.key_file).read().strip()
S = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), f"p170_{a.set}.json"), encoding="utf-8"))
doc, items = S["doc"], S["items"][: a.only or None]
H = {"Content-Type": "application/json", "Authorization": "Bearer " + key}


def post(path, body, timeout=7200):
    req = urllib.request.Request(a.base.rstrip("/") + path, data=json.dumps(body).encode(), headers=H)
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read())


def ntok(text):
    return len(post("/tokenize", {"content": text}, 600)["tokens"])


STOP = set("""a an the of to in on at for by with from as is are was were be been being it its this that these those
which what who whom whose how many much when where why do does did done can could may might must shall should will would
and or not no yes than then there their them they he she his her him we our us you your i me my one some any each
above below code answer number only value constant give name use used using into out over under after before
about per kind""".split())


def words(t):
    out = []
    for w in re.findall(r"[A-Za-z0-9_.]+", t):
        w = w.strip(".")
        if not w:
            continue
        out.append(w.lower())
        parts = re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])|\d+(?:\.\d+)?", w)
        if len(parts) > 1:
            out += [p.lower() for p in parts]
    return [w for w in out if w not in STOP and len(w) > 1]


def chunks_of(text, cap):
    blocks = re.split(r"(\n\s*\n)", text)
    out, cur = [], ""
    for b in blocks:
        if len(cur) + len(b) <= cap:
            cur += b
            continue
        if cur:
            out.append(cur)
        cur = ""
        while len(b) > cap:  # a long block is cut at line ends (or at the cap)
            cut = b.rfind("\n", 0, cap)
            cut = cut if cut > cap // 4 else cap
            out.append(b[:cut])
            b = b[cut:]
        cur = b
    if cur:
        out.append(cur)
    return out


def select(question, n_item):
    ch = chunks_of(doc, a.chunk_chars)
    ratio = len(doc) / NDOC
    est = [max(1, round(len(c) / ratio)) for c in ch]
    toks = [words(c) for c in ch]
    df = Counter(w for t in toks for w in set(t))
    N = len(ch)
    avg = sum(len(t) for t in toks) / N
    q = [w for w in dict.fromkeys(words(question))]
    score = []
    for t in toks:
        tf = Counter(t)
        s = 0.0
        for w in q:
            if tf[w]:
                idf = math.log(1 + (N - df[w] + 0.5) / (df[w] + 0.5))
                s += idf * tf[w] * 2.2 / (tf[w] + 1.2 * (0.25 + 0.75 * len(t) / avg))
        score.append(s)
    keep, used = set(), 0
    i = 0
    while i < N and used < a.sinks:
        keep.add(i); used += est[i]; i += 1
    j = N - 1
    w_used = 0
    while j >= 0 and w_used < a.window:
        keep.add(j); w_used += est[j]; used += est[j]; j -= 1
    lex_rank = [k for k in sorted(range(N), key=lambda k: -score[k]) if score[k] > 0]
    if a.arm in ("small", "mix"):
        sm = SMALL["items"][n_item - 1]
        assert len(sm) == N, "the scores file has another chunk count"
        sm_rank = sorted(range(N), key=lambda k: -sm[k])
    if a.arm == "lex":
        order_pick = lex_rank
    elif a.arm == "small":
        order_pick, score = sm_rank, sm
    else:  # mix: one from the small-model ranking, then one from the text-match ranking, and so on
        order_pick, seen = [], set()
        for x, y in zip(sm_rank, lex_rank + sm_rank):
            for k in (x, y):
                if k not in seen:
                    seen.add(k); order_pick.append(k)
        score = [max(sm[k], 0.0) for k in range(N)]
    for k in order_pick:
        if used >= a.keep:
            break
        if k not in keep:
            keep.add(k); used += est[k]
    order = sorted(keep)
    text, prev = "", -1
    for k in order:
        if prev >= 0 and k != prev + 1:
            text += "\n\n[...]\n\n"
        text += ch[k]
        prev = k
    ranked = sorted(range(N), key=lambda k: -score[k])
    return text, ranked, ch, score, len(order)


def grade(ans, it):
    t = ans.lower()
    if a.set == "code":
        m = re.findall(r"-?\d+(?:\.\d+)?", ans)
        return bool(m) and m[0] == it["ans"][0]
    return any(k in t for k in it["ans"])


SMALL = json.load(open(rf"C:/bonsai/8gb/p170/scores_{a.set}.json")) if a.arm in ("small", "mix") else None
NDOC = ntok(doc)
print(json.dumps({"set": a.set, "arm": a.arm, "doc_tokens": NDOC, "items": len(items)}), flush=True)
for n, it in enumerate(items, 1):
    rec = {"set": a.set, "arm": a.arm, "keep": a.keep if a.arm != "dense" else None, "item": n, "pos": it["pos"],
           "want": it["ans"], "named": it.get("named")}
    if a.arm != "dense":
        t0 = time.time()
        text, ranked, ch, score, nk = select(it["q"], n)
        fact_chunk = next((k for k, c in enumerate(ch) if it["fact"] in c), None)
        rec.update(select_s=round(time.time() - t0, 2), chunks_kept=nk, fact_kept=it["fact"] in text,
                   fact_rank=(ranked.index(fact_chunk) + 1) if fact_chunk is not None else None,
                   fact_score=round(score[fact_chunk], 2) if fact_chunk is not None else None)
    else:
        text = doc
    body = {"messages": [{"role": "user", "content": text + "\n\n" + it["q"]}], "max_tokens": 24, "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": False}, "logprobs": True, "top_logprobs": 20}
    if a.dry:
        print(json.dumps(rec), flush=True)
        continue
    t0 = time.time()
    try:
        r = post("/v1/chat/completions", body)
        ans = r["choices"][0]["message"].get("content") or ""
        tm = r.get("timings", {})
        lp = ((r["choices"][0].get("logprobs") or {}).get("content") or [])
        rec["lp"] = [[t.get("token"), round(t.get("logprob", 0.0), 5),
                      [[u.get("token"), round(u.get("logprob", 0.0), 5)] for u in (t.get("top_logprobs") or [])]] for t in lp]
        rec.update(answer=ans.strip()[:300], ok=grade(ans, it), prompt_n=tm.get("prompt_n"),
                   prefill_tps=round(tm.get("prompt_per_second") or 0, 1), wall_s=round(time.time() - t0, 1))
    except Exception as e:  # noqa: BLE001
        rec.update(error=repr(e)[:200], ok=False, wall_s=round(time.time() - t0, 1))
    print(json.dumps(rec), flush=True)
    with open(a.out, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")
