"""E1: does a sandboxed code-execution tool fix long-computation failures?

Arms (A server, A sampling profile, budget 20480, max_tokens 32768 per response):
  NT  no tools: single chat turn (the H2 B20 baseline behaviour)
  CT  tool run_python(code, stdin) executed in CPython-on-WASI (tooling/wasi-python/sandbox.py: no host files,
      no network, no processes, 128 MB, 10 s); up to 8 model responses; final answer = last "ANSWER: <int>"
The model's code only ever runs inside the WASI sandbox.
"""
import argparse
import json
import os
import re
import sys
import time

import puzzles
from run import post

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "tooling", "wasi-python"))
import sandbox  # noqa: E402

TOOLS = [{"type": "function", "function": {
    "name": "run_python",
    "description": "Run a Python 3.12 program in an isolated sandbox (standard library only, no network, no files "
                   "outside the working directory, 10 second limit). Returns exit code, stdout and stderr.",
    "parameters": {"type": "object", "properties": {
        "code": {"type": "string", "description": "the complete program"},
        "stdin": {"type": "string", "description": "optional standard input"}}, "required": ["code"]}}}]
PROFILE = dict(temperature=1.0, top_p=0.95, top_k=20, min_p=0.05, repeat_penalty=1.0, presence_penalty=0.0,
               reasoning_format="deepseek", reasoning_effort="medium",
               chat_template_kwargs={"reasoning_effort": "medium"}, reasoning_budget_tokens=20480,
               max_tokens=32768, stream=False, cache_prompt=True)


def parse_answer(text):
    f = re.findall(r"ANSWER:\s*\**\s*(-?[\d,]+)", text or "")
    return int(f[-1].replace(",", "")) if f else None


def attempt(kind, seed, arm, out_dir, max_responses=8):
    q, truth = puzzles.make(kind, seed)
    msgs = [{"role": "user", "content": q}]
    log, t0, tokens, ans, execs = [], time.time(), 0, None, 0
    for step in range(max_responses if arm == "CT" else 1):
        body = dict(PROFILE, model="bonsai-2-27b", messages=msgs, seed=seed * 7 + 11 + step)
        if arm == "CT":
            body["tools"] = TOOLS
        r = post("/v1/chat/completions", body, 3600)
        m = r["choices"][0]["message"]
        tokens += r["usage"]["completion_tokens"]
        log.append({"step": step, "message": m, "usage": r["usage"]})
        am = {"role": "assistant", "content": m.get("content") or ""}
        if m.get("reasoning_content"):
            am["reasoning_content"] = m["reasoning_content"]
        calls = m.get("tool_calls") or []
        if calls:
            am["tool_calls"] = calls
        msgs.append(am)
        a = parse_answer(m.get("content"))
        if a is not None and not calls:
            ans = a
            break
        if not calls:
            if arm == "CT":
                msgs.append({"role": "user", "content": "Finish with a final line ANSWER: <integer>."})
                continue
            break
        for c in calls:
            try:
                args = json.loads(c["function"]["arguments"])
                res = sandbox.run({"main.py": args.get("code", "")}, ["/work/main.py"],
                                  stdin=(args.get("stdin") or "").encode("utf-8"), timeout=10)
                out = {"exit_code": res["exit_code"], "timed_out": res["timed_out"],
                       "stdout": res["stdout"][:8000].decode("utf-8", "replace"),
                       "stderr": res["stderr"][-4000:].decode("utf-8", "replace")}
                execs += 1
            except Exception as e:
                out = {"error": f"tool call rejected: {e!r}"[:500]}
            log.append({"step": step, "tool": out})
            msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": "run_python",
                         "content": json.dumps(out, ensure_ascii=False)})
    rec = dict(kind=kind, seed=seed, arm=arm, truth=truth, answer=ans, correct=ans == truth, tokens=tokens,
               responses=sum(1 for x in log if "message" in x), execs=execs, wall_s=round(time.time() - t0, 1))
    os.makedirs(out_dir, exist_ok=True)
    json.dump(dict(rec, log=log), open(os.path.join(out_dir, f"{kind}-{seed}-{arm}.json"), "w", encoding="utf-8"),
              ensure_ascii=False)
    return rec


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    for k, s, arm in json.load(open(a.plan))["order"]:
        if os.path.exists(os.path.join(a.out, f"{k}-{s}-{arm}.json")):
            continue
        r = attempt(k, s, arm, a.out)
        print(json.dumps(r), flush=True)
