"""Single-turn budget comparison. Arms differ only in reasoning_budget_tokens; max_tokens equal in both."""
import argparse
import hashlib
import json
import os
import re
import time
import urllib.request

import puzzles
from run import KEY, BASE

ARMS = {"B20": 20480, "B40": 40960, "B12": 12288, "T10": 40960, "T06": 40960,
        "V12a": 12288, "V12b": 12288, "V12c": 12288, "B80": 81920,
        "N20": 20480}
SEEDOFF = {"V12b": 1000, "V12c": 2000}
TEMP = {"T06": 0.6}
BUDGET_MSG = "Now produce the complete answer."
NOTICE = ("You have a thinking budget of about 20,000 tokens. If you use it up, your thinking is cut off and you "
          "must answer immediately. Choose a method that fits in that budget and leave room to check the result.")


def ask(kind, seed, arm, out_dir, max_tokens=49152, timeout=1800):
    q, truth = puzzles.make(kind, seed)
    body = dict(model="bonsai-2-27b", messages=([{"role": "system", "content": NOTICE}] if arm == "N20" else []) + [{"role": "user", "content": q}], temperature=TEMP.get(arm, 1.0), top_p=0.95,
                top_k=20, min_p=0.05, repeat_penalty=1.0, presence_penalty=0.0, reasoning_format="deepseek",
                reasoning_effort="medium", chat_template_kwargs={"reasoning_effort": "medium"},
                reasoning_budget_tokens=ARMS[arm], max_tokens=max_tokens, stream=False, cache_prompt=False,
                seed=seed * 7 + 11 + SEEDOFF.get(arm, 0))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{kind}-{seed}-{arm}.json")
    rec = {"kind": kind, "seed": seed, "arm": arm, "truth": truth,
           "request_sha256": hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()}
    t0 = time.time()
    try:
        req = urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(), method="POST",
                                     headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
        resp = json.loads(urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8"))
    except Exception as e:
        rec.update(status="infra_error", error=repr(e)[:300], wall_s=round(time.time() - t0, 1))
        json.dump(rec, open(path, "w", encoding="utf-8"))
        return rec
    m = resp["choices"][0]["message"]
    content, rc = m.get("content") or "", m.get("reasoning_content") or ""
    found = re.findall(r"ANSWER:\s*\**\s*(-?[\d,]+)", content)
    ans = int(found[-1].replace(",", "")) if found else None
    rec.update(status="ok", answer=ans, correct=(ans == truth), forced=BUDGET_MSG in rc or BUDGET_MSG in content,
               finish=resp["choices"][0].get("finish_reason"), completion_tokens=resp["usage"]["completion_tokens"],
               reasoning_chars=len(rc), content_chars=len(content), wall_s=round(time.time() - t0, 1),
               draft_n=(resp.get("timings") or {}).get("draft_n"), response=resp)
    json.dump(rec, open(path, "w", encoding="utf-8"), ensure_ascii=False)
    return rec


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    plan = json.load(open(a.plan))
    for k, s, arm in plan["order"]:
        p = os.path.join(a.out, f"{k}-{s}-{arm}.json")
        if os.path.exists(p) and json.load(open(p, encoding="utf-8")).get("status") == "ok":
            continue
        r = ask(k, s, arm, a.out, **plan.get("limits", {}))
        print(json.dumps({x: r.get(x) for x in ("kind", "seed", "arm", "truth", "answer", "correct", "forced", "finish",
                                                 "completion_tokens", "wall_s")}), flush=True)
