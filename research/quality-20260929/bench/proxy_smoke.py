"""End-to-end check of tooling/interpreter_proxy.py: a plain client request (no tools) through :8081."""
import json, time, urllib.request
from run import KEY
import puzzles
q, truth = puzzles.make("knapsack", 1)
body = {"model": "bonsai-2-27b", "messages": [{"role": "user", "content": q}], "temperature": 1.0, "top_p": 0.95,
        "top_k": 20, "min_p": 0.05, "reasoning_format": "deepseek", "max_tokens": 32768, "seed": 5}
t0 = time.time()
req = urllib.request.Request("http://127.0.0.1:8081/v1/chat/completions", data=json.dumps(body).encode(),
                             headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
r = json.loads(urllib.request.urlopen(req, timeout=3600).read())
c = r["choices"][0]["message"].get("content") or ""
import re
f = re.findall(r"ANSWER:\s*\**\s*(-?[\d,]+)", c)
ans = int(f[-1].replace(",", "")) if f else None
print(json.dumps({"truth": truth, "answer": ans, "correct": ans == truth, "tool_calls_returned": bool(r["choices"][0]["message"].get("tool_calls")),
                  "interpreter_runs": len(r.get("interpreter_trace", [])), "trace": r.get("interpreter_trace"),
                  "usage": r.get("usage"), "wall_s": round(time.time() - t0, 1)}))
