"""Plain chat requests through the live layer (:8080), one per puzzle, with per-request layer options.

Arms (all through the layer; the layer decides whether to offer run_python):
  P    layer defaults                         (interpreter on, no input file)
  PF   + "input_file": true                   (the user's text is available to run_python as input.txt)
  PS   layer defaults, stream=true            (the streaming interpreter path; the SSE stream is reassembled here)
  PFS  "input_file": true, stream=true
  D    direct to llama-server (:18080), no tools (the raw model)
Records correct / tokens / sandbox runs / code chars per run, plus the full response.
"""
import argparse
import hashlib
import json
import os
import re
import time
import urllib.request

import puzzles
from run import KEY

LAYER = "http://127.0.0.1:8080"
DIRECT = "http://127.0.0.1:18080"
ARMS = {"P": {}, "PF": {"input_file": True}, "PS": {"stream": True}, "PFS": {"input_file": True, "stream": True}, "D": {}}
PROFILE = dict(temperature=1.0, top_p=0.95, top_k=20, min_p=0.05, repeat_penalty=1.0, presence_penalty=0.0,
               reasoning_format="deepseek", reasoning_effort="medium", chat_template_kwargs={"reasoning_effort": "medium"},
               reasoning_budget_tokens=20480, max_tokens=32768, cache_prompt=True)


def parse_answer(text):
    f = re.findall(r"ANSWER:\s*\**\s*(-?[\d,]+)", text or "")
    return int(f[-1].replace(",", "")) if f else None


def reassemble(raw):
    """Fold an SSE stream into one chat.completion-shaped dict (content, reasoning, finish, usage, tool-call leaks)."""
    content, reasoning, finish, usage, leaks, chunks, notes = [], [], None, None, 0, 0, 0
    for line in raw.decode("utf-8", "replace").split(chr(10)):
        if not line.startswith("data: ") or line.strip() == "data: [DONE]":
            continue
        chunks += 1
        ev = json.loads(line[6:])
        if ev.get("usage"):
            usage = ev["usage"]
        for ch in ev.get("choices") or []:
            d = ch.get("delta") or {}
            if isinstance(d.get("content"), str):
                content.append(d["content"])
            if isinstance(d.get("reasoning_content"), str):
                reasoning.append(d["reasoning_content"])
                notes += d["reasoning_content"].count("[run_python:")
            if d.get("tool_calls"):
                leaks += 1
            finish = ch.get("finish_reason") or finish
    return {"choices": [{"message": {"content": "".join(content), "reasoning_content": "".join(reasoning)}, "finish_reason": finish}],
            "usage": usage or {}, "stream_chunks": chunks, "tool_call_deltas_leaked": leaks, "run_notes": notes}


def ask(kind, seed, arm, out_dir, timeout=3600):
    q, truth = puzzles.make(kind, seed)
    opts = ARMS[arm]
    base = DIRECT if arm == "D" else LAYER
    body = dict(PROFILE, model="bonsai-2-27b", messages=[{"role": "user", "content": q}], seed=seed * 7 + 11, stream=False)
    body.update(opts)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{kind}-{seed}-{arm}.json")
    rec = {"kind": kind, "seed": seed, "arm": arm, "truth": truth,
           "request_sha256": hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()}
    t0 = time.time()
    try:
        req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(), method="POST",
                                     headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
        raw = urllib.request.urlopen(req, timeout=timeout).read()
        resp = reassemble(raw) if body.get("stream") else json.loads(raw.decode("utf-8"))
    except Exception as e:
        rec.update(status="infra_error", error=repr(e)[:300], wall_s=round(time.time() - t0, 1))
        json.dump(rec, open(path, "w", encoding="utf-8"))
        return rec
    m = resp["choices"][0]["message"]
    content = m.get("content") or ""
    ans = parse_answer(content)
    trace = resp.get("interpreter_trace") or []
    rec.update(status="ok", answer=ans, correct=(ans == truth), finish=resp["choices"][0].get("finish_reason"),
               completion_tokens=(resp.get("usage") or {}).get("completion_tokens"),
               runs=len(trace) if not body.get("stream") else resp.get("run_notes"),
               code_chars=[t.get("code_chars") for t in trace], exits=[t.get("exit_code") for t in trace],
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
    for k, s, arm in plan["order"]:
        p = os.path.join(a.out, f"{k}-{s}-{arm}.json")
        if os.path.exists(p) and json.load(open(p, encoding="utf-8")).get("status") == "ok":
            continue
        r = ask(k, s, arm, a.out)
        print(json.dumps({x: r.get(x) for x in ("kind", "seed", "arm", "truth", "answer", "correct", "finish",
                                                 "completion_tokens", "runs", "code_chars", "wall_s", "status")}), flush=True)
