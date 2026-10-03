"""AIME 2025 (math-ai/aime25, 30 problems), one plain chat request per problem, paired raw vs layer.

Arms: RAW = llama-server on :18080 (no tools); PROD = the layer on :8080 (plain request, so the layer offers its
sandboxed Python tool). Same prompt, same sampling, same seed. Answer = last \\boxed{...} (or the last integer on
a final "answer" line); AIME answers are integers 0-999.
"""
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
SUFFIX = chr(10) + chr(10) + "Please reason step by step, and put your final answer within \\boxed{}."
PROFILE = dict(temperature=1.0, top_p=0.95, top_k=20, min_p=0.05, repeat_penalty=1.0, presence_penalty=0.0,
               reasoning_format="deepseek", reasoning_effort="medium", chat_template_kwargs={"reasoning_effort": "medium"},
               reasoning_budget_tokens=20480, max_tokens=32768, cache_prompt=True, stream=False)


DATASET = "aime25_rows.json"   # overridden by the plan's "dataset_file"


def problems():
    d = json.load(open(os.path.join(HERE, DATASET), encoding="utf-8"))
    return [(int(r["row"]["id"]), r["row"]["problem"], str(r["row"]["answer"]).strip()) for r in d["rows"]]


def parse_answer(text):
    text = text or ""
    boxes = re.findall(r"\\boxed\{([^{}]*)\}", text)
    cands = boxes or re.findall(r"(?i)answer[^0-9\-]{0,20}(-?\d+)", text)
    if not cands:
        return None
    m = re.search(r"-?\d+", cands[-1].replace(",", ""))
    return int(m.group()) if m else None


def ask(pid, prob, truth, arm, seed, out_dir, timeout=3600):
    body = dict(PROFILE, model="bonsai-2-27b", messages=[{"role": "user", "content": prob + SUFFIX}], seed=seed)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"aime-{pid:02d}-{seed}-{arm}.json")
    rec = {"pid": pid, "seed": seed, "arm": arm, "truth": int(truth),
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
    ans = parse_answer(content)
    trace = resp.get("interpreter_trace") or []
    rec.update(status="ok", answer=ans, correct=(ans == int(truth)), finish=resp["choices"][0].get("finish_reason"),
               completion_tokens=(resp.get("usage") or {}).get("completion_tokens"), runs=len(trace),
               exits=[t.get("exit_code") for t in trace], reasoning_chars=len(m.get("reasoning_content") or ""),
               content_chars=len(content), wall_s=round(time.time() - t0, 1), response=resp)
    json.dump(rec, open(path, "w", encoding="utf-8"), ensure_ascii=False)
    return rec


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    plan = json.load(open(a.plan))
    DATASET = plan.get("dataset_file", DATASET)
    probs = {pid: (p, t) for pid, p, t in problems()}
    for pid, seed, arm in plan["order"]:
        path = os.path.join(a.out, f"aime-{pid:02d}-{seed}-{arm}.json")
        if os.path.exists(path) and json.load(open(path, encoding="utf-8")).get("status") == "ok":
            continue
        p, t = probs[pid]
        r = ask(pid, p, t, arm, seed, a.out)
        print(json.dumps({k: r.get(k) for k in ("pid", "seed", "arm", "truth", "answer", "correct", "finish",
                                                 "completion_tokens", "runs", "wall_s", "status")}), flush=True)
