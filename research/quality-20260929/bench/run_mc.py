"""Multiple-choice knowledge questions (MMLU-Pro sample), one plain chat request each, paired raw vs layer.
Neutrality check: the layer's levers (API cards, Python tool) should not matter here; the question is whether
offering the tool costs accuracy or tokens on questions that do not need it."""
import argparse
import hashlib
import json
import os
import re
import time
import urllib.request

from run import KEY

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = {"RAW": "http://127.0.0.1:18080", "PROD": "http://127.0.0.1:8080"}
LETTERS = "ABCDEFGHIJ"
PROFILE = dict(temperature=1.0, top_p=0.95, top_k=20, min_p=0.05, repeat_penalty=1.0, presence_penalty=0.0,
               reasoning_format="deepseek", reasoning_effort="medium", chat_template_kwargs={"reasoning_effort": "medium"},
               reasoning_budget_tokens=20480, max_tokens=32768, cache_prompt=True, stream=False)


def questions(path):
    d = json.load(open(os.path.join(HERE, path), encoding="utf-8"))
    out = []
    for r in d["rows"]:
        r = r["row"]
        opts = "\n".join(f"{LETTERS[i]}. {o}" for i, o in enumerate(r["options"]))
        prompt = (f"{r['question']}\n\nOptions:\n{opts}\n\nThink step by step, then give the letter of the single best answer "
                  f"within \\boxed{{}}.")
        out.append((int(r["id"]), prompt, r["answer"].strip().upper(), r.get("category")))
    return out


def parse_letter(text):
    text = text or ""
    boxes = re.findall(r"\\boxed\{\s*\(?([A-J])\)?\s*\}", text)
    if boxes:
        return boxes[-1]
    m = re.findall(r"(?i)answer[^A-J]{0,20}\(?\b([A-J])\b\)?", text)
    return m[-1].upper() if m else None


def ask(qid, prompt, truth, cat, arm, seed, out_dir, timeout=3600):
    body = dict(PROFILE, model="bonsai-2-27b", messages=[{"role": "user", "content": prompt}], seed=seed)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"mc-{qid:03d}-{seed}-{arm}.json")
    rec = {"qid": qid, "seed": seed, "arm": arm, "truth": truth, "category": cat,
           "request_sha256": hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()}
    t0 = time.time()
    try:
        req = urllib.request.Request(BASE[arm] + "/v1/chat/completions", data=json.dumps(body).encode(), method="POST",
                                     headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
        resp = json.loads(urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8"))
    except Exception as e:
        rec.update(status="infra_error", error=repr(e)[:300], wall_s=round(time.time() - t0, 1))
        json.dump(rec, open(path, "w", encoding="utf-8"))
        return rec
    m = resp["choices"][0]["message"]
    content = m.get("content") or ""
    ans = parse_letter(content)
    trace = resp.get("interpreter_trace") or []
    rec.update(status="ok", answer=ans, correct=(ans == truth), finish=resp["choices"][0].get("finish_reason"),
               completion_tokens=(resp.get("usage") or {}).get("completion_tokens"), runs=len(trace),
               reasoning_chars=len(m.get("reasoning_content") or ""), content_chars=len(content),
               wall_s=round(time.time() - t0, 1), response=resp)
    json.dump(rec, open(path, "w", encoding="utf-8"), ensure_ascii=False)
    return rec


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    plan = json.load(open(a.plan))
    qs = {qid: (p, t, c) for qid, p, t, c in questions(plan["dataset_file"])}
    for qid, seed, arm in plan["order"]:
        path = os.path.join(a.out, f"mc-{qid:03d}-{seed}-{arm}.json")
        if os.path.exists(path) and json.load(open(path, encoding="utf-8")).get("status") == "ok":
            continue
        p, t, c = qs[qid]
        r = ask(qid, p, t, c, arm, seed, a.out)
        print(json.dumps({k: r.get(k) for k in ("qid", "seed", "arm", "truth", "answer", "correct", "finish",
                                                 "completion_tokens", "runs", "wall_s", "status")}), flush=True)
